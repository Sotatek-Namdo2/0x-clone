// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

contract LPStaking is Initializable {
    uint256 private constant HUNDRED_PERCENT = 100_000_000;
    uint256 private constant DAY = 86400;
    uint256 private constant YEAR = 86400 * 365;
    uint256 private constant ONE_LP = 1e18;
    string private constant SEPARATOR = "#";

    // ----- Structs -----
    struct LPStakeEntity {
        uint256 amount;
        uint256 rewardDebt;
        uint256 creationTime;
        uint256 withdrawn;
    }

    struct UserLPStakeInfo {
        uint8 size;
        mapping(uint8 => LPStakeEntity) entities;
    }

    struct PoolInfo {
        string name;
        IERC20 lpToken;
        uint256 lpAmountInPool;
        uint256 totalDistribute;
        uint256 startTime;
        uint256 duration;
        uint256 acc0xBPerShare;
        uint256 lastRewardTimestamp;
    }

    // ----- Contract Storage -----
    uint256 public lpStakingEntitiesLimit;

    // ----- Limits on withdrawal -----
    uint256 public withdrawTimeout;
    uint256[] public withdrawTaxLevel;
    uint256[] public withdrawTaxPortion;
    address public earlyWithdrawTaxPool;

    PoolInfo[] public pools;
    mapping(uint32 => mapping(address => UserLPStakeInfo)) public userInfo;
    mapping(address => bool) private whitelistAuthorities;

    // ----- Router Addresses -----
    address public token0xBAddress;
    address public admin0xB;

    // ----- Constructor -----
    function initialize() public initializer {
        admin0xB = msg.sender;
        lpStakingEntitiesLimit = 100;
        withdrawTimeout = 0;
        withdrawTaxLevel = [0, 0, DAY * 30, DAY * 60];
        withdrawTaxPortion = [5_000_000, 5_000_000, 2_500_000, 0];
        earlyWithdrawTaxPool = msg.sender;
    }

    // solhint-disable-next-line
    receive() external payable {}

    // ----- Events -----

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token0xBAddress || msg.sender == admin0xB || isWhitelisted(msg.sender), "Access Denied!");
        _;
    }

    // ----- External READ functions -----
    /**
        @notice return a JSON includes all info of a pool
        @param _poolId index of pool
        @return res JSON
    */
    /* solhint-disable */
    function getJSONSinglePoolInfo(uint32 _poolId) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong pool id");
        PoolInfo memory pool = pools[_poolId];
        res = string(abi.encodePacked('{"index":"', uint2str(_poolId), '","name":"'));
        res = string(abi.encodePacked(res, pool.name, '","lpTokenAddress":"'));
        res = string(abi.encodePacked(res, toAsciiString(address(pool.lpToken)), '","lpAmountInPool":"'));
        res = string(abi.encodePacked(res, uint2str(pool.lpAmountInPool), '","totalDistribute":"'));
        res = string(abi.encodePacked(res, uint2str(pool.totalDistribute), '","startTime":"'));
        res = string(abi.encodePacked(res, uint2str(pool.startTime), '","duration":"'));
        res = string(abi.encodePacked(res, uint2str(pool.duration), '","acc0xBPerShare":"'));
        res = string(abi.encodePacked(res, uint2str(pool.acc0xBPerShare), '","lastRewardTimestamp":"'));
        res = string(abi.encodePacked(res, uint2str(pool.lastRewardTimestamp), '"}'));
    }

    /**
        @notice return a JSON includes all info of an user in a pool
        @param _poolId index of pool
        @param _user address of an user
        @return res JSON
    */
    function getJSONSinglePoolUser(uint32 _poolId, address _user) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong pool id");
        res = string(abi.encodePacked('{"index":"', uint2str(_poolId), '","stakedAmount":"'));
        res = string(abi.encodePacked(res, uint2str(totalStakeOfUser(_poolId, _user)), '","pendingReward":"'));
        (, uint256 pendingRw) = getUserPendingReward(_poolId, _user);
        res = string(abi.encodePacked(res, uint2str(pendingRw), '","minTimestamp":"'));
        (, uint256 minTstamp) = getUserTimestamps(_poolId, _user);
        res = string(abi.encodePacked(res, uint2str(minTstamp), '"}'));
    }

    /**
        @notice return a JSON includes info of all pool, can choose to get only active pools or not
        @param _onlyActive decide if only return info of active pool
        @return res JSON
    */
    function getJSONAllPoolsInfo(bool _onlyActive) public view returns (string memory res) {
        res = "{";
        for (uint32 _pi = 0; _pi < pools.length; _pi++) {
            if (!_onlyActive || isPoolActive(pools[_pi])) {
                res = string(abi.encodePacked(res, '"', uint2str(_pi), '":', getJSONSinglePoolInfo(_pi), ","));
            }
        }
        res = string(abi.encodePacked(res, '"info":""}'));
    }

    /**
        @notice return a JSON includes info of all pool that specific to an user,
        can choose to get only active pools or not
        @param _onlyActive decide if only return info of active pool
        @param _user address of an user
        @return res JSON
    */
    function getJSONAllPoolsUser(bool _onlyActive, address _user) public view returns (string memory res) {
        res = "{";
        for (uint32 _pi = 0; _pi < pools.length; _pi++) {
            if (!_onlyActive || isPoolActive(pools[_pi])) {
                res = string(abi.encodePacked(res, '"', uint2str(_pi), '":', getJSONSinglePoolUser(_pi, _user), ","));
            }
        }
        res = string(abi.encodePacked(res, '"user":""}'));
    }

    /* solhint-enable */

    /**
        @notice number of pools 
        @return len number of pools
    */
    function getPoolsCount() public view returns (uint256) {
        return pools.length;
    }

    /**
        @notice calculate the current APR of one LP pool
        @param _poolId index of pool
        @return apr current APR of an LP pool
    */
    function getAPR(uint32 _poolId) public view returns (uint256 apr) {
        require(_poolId < pools.length, "wrong id");
        PoolInfo memory pool = pools[_poolId];
        apr = (pool.totalDistribute * YEAR * uint256(1e18)) / pool.duration / pool.lpAmountInPool;
    }

    /**
        @notice calculate total stake of one address in a pool
        @param _poolId index of pool
        @param addr address of the user
        @return totalStake total amount of LP staked in the user
    */
    function totalStakeOfUser(uint32 _poolId, address addr) public view returns (uint256 totalStake) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        totalStake = 0;
        for (uint8 i = 1; i < user.size; i++) {
            totalStake += user.entities[i].amount;
        }
    }

    /**
        @notice get the timestamps of every entity that user staked in one pool
        @dev result is returned as a string, which entities is separated with SEPARATOR
        @param _poolId index of pool
        @param addr address of user
        @return res result as a string
    */
    function getUserTimestamps(uint32 _poolId, address addr) public view returns (string memory res, uint256 minTs) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        minTs = 2**256 - 1;
        if (user.size == 0) {
            return ("", minTs);
        }
        res = uint2str(user.entities[0].creationTime);
        for (uint8 i = 1; i < user.size; i++) {
            uint256 creatime = user.entities[i].creationTime;
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(creatime)));
            if (creatime < minTs) minTs = creatime;
        }
    }

    /**
        @notice get the stake amount of every entity that user staked in one pool
        @dev result is returned as a string, which entities is separated with SEPARATOR
        @dev for each entity, the amount staked at first is separated into 2 variable: amount + withdrawn
        @param _poolId index of pool
        @param addr address of user
        @return res result as a string
    */
    function getUserStakeAmounts(uint32 _poolId, address addr) public view returns (string memory res, uint256 ttl) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return ("", 0);
        }
        ttl = 0;
        res = uint2str(user.entities[0].amount + user.entities[0].withdrawn);
        for (uint8 i = 1; i < user.size; i++) {
            uint256 amount = user.entities[i].amount + user.entities[i].withdrawn;
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(amount)));
            ttl += amount;
        }
    }

    /**
        @notice get the pending rewards of every entity that user staked in one pool
        @dev result is returned as a string, which entities is separated with SEPARATOR
        @param _poolId index of pool
        @param addr address of user
        @return res result as a string
    */
    function getUserPendingReward(uint32 _poolId, address addr) public view returns (string memory res, uint256 ttl) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return ("", 0);
        }
        ttl = 0;
        res = uint2str(pendingReward(_poolId, addr, 0));
        for (uint8 i = 1; i < user.size; i++) {
            uint256 rw = pendingReward(_poolId, addr, i);
            ttl += rw;
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(rw)));
        }
    }

    /**
        @notice get the unstaked amount of every entity that user staked in one pool
        @dev result is returned as a string, which entities is separated with SEPARATOR
        @param _poolId index of pool
        @param addr address of user
        @return res result as a string
    */
    function getUserUnstakedAmount(uint32 _poolId, address addr) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return "";
        }
        res = uint2str(user.entities[0].withdrawn);
        for (uint8 i = 1; i < user.size; i++) {
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(user.entities[i].withdrawn)));
        }
    }

    /**
        @notice calculate the unclaimed reward of a user in one entity
        @dev the accumulated reward per share is considered, add with reward from latest pool update
        @dev using current state of pool (total lp in pool).
        @dev the formula is: (a * n) + delta(now - l) * c - rewardDebt
        @dev a: accumulatedRewardPerShare in pool, n: total share, delta(now - l): seconds since last update
        @dev c: current reward per share per second, rewardDebt: reward already claimed by user in this pool
        @param _poolId id of pool
        @param addr address of user
        @param _index index of some entity
        @return reward pending reward of user
    */
    function pendingReward(
        uint32 _poolId,
        address addr,
        uint32 _index
    ) public view returns (uint256) {
        require(_poolId < pools.length, "wrong id");
        PoolInfo memory pool = pools[_poolId];
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        LPStakeEntity memory entity = user.entities[uint8(_index)];
        uint256 acc0xBPerShare = pool.acc0xBPerShare;
        uint256 lpSupply = pool.lpAmountInPool;
        if (block.timestamp > pool.lastRewardTimestamp && lpSupply != 0) {
            uint256 reward = getDelta(pool.lastRewardTimestamp, block.timestamp) * getCurrentRewardPerLPPerSecond(pool);
            acc0xBPerShare = acc0xBPerShare + (reward * ONE_LP) / lpSupply;
        }
        return (entity.amount * acc0xBPerShare) / ONE_LP - entity.rewardDebt;
    }

    /**
        @notice show if an address is whitelisted to create a pool
        @param addr address to query
        @return isWhitelisted true if `addr` is whitelisted
    */
    function isWhitelisted(address addr) public view returns (bool) {
        return whitelistAuthorities[addr];
    }

    /**
        @notice show if an entity is withdrawable
        @param _poolId index of a pool
        @param addr address of an entity owner
        @param _index index of entity
        @return withdrawable true if the entity is withdrawable
    */
    function withdrawable(
        uint32 _poolId,
        address addr,
        uint32 _index
    ) public view returns (bool) {
        require(_poolId < pools.length, "wrong id");
        LPStakeEntity memory entity = userInfo[_poolId][addr].entities[uint8(_index)];
        return (entity.creationTime + withdrawTimeout < block.timestamp);
    }

    /**
        @notice return current tax of an entity
        @param _poolId index of a pool
        @param addr address of an entity owner
        @param _index index of entity
        @return tax amount of tax of an entity
    */
    function taxOfEntity(
        uint32 _poolId,
        address addr,
        uint32 _index
    ) public view returns (uint256) {
        require(_poolId < pools.length, "wrong id");
        LPStakeEntity memory entity = userInfo[_poolId][addr].entities[uint8(_index)];
        uint256 durationSinceStart = block.timestamp - entity.creationTime;
        for (uint256 i = withdrawTaxPortion.length - 1; i > 0; i--) {
            if (withdrawTaxLevel[i] <= durationSinceStart) {
                return withdrawTaxPortion[i];
            }
        }
        return 0;
    }

    // ----- Admin WRITE functions -----
    /**
        @notice set address of 0xB token
        @param _token address of 0xB
    */
    function setToken(address _token) external onlyAuthorities {
        require(_token != address(0), "NEW_TOKEN: zero addr");
        token0xBAddress = _token;
    }

    function setTaxLevels(uint256[] memory _newLevels) external onlyAuthorities {
        require(_newLevels.length == 4, "please write 4 levels");
        require(
            _newLevels[0] == 0 &&
                _newLevels[1] >= _newLevels[0] &&
                _newLevels[2] >= _newLevels[1] &&
                _newLevels[3] >= _newLevels[2],
            "levels must be non-decreasing"
        );
        withdrawTaxLevel = _newLevels;
    }

    /**
        @notice set new withdrawal timeout
        @param _timeout new timeout
    */
    function setWithdrawTimeout(uint256 _timeout) external onlyAuthorities {
        withdrawTimeout = _timeout;
    }

    /**
        @notice set new withdrawal tax pool
        @param _pool new tax pool
    */
    function setWithdrawTaxPool(address _pool) external onlyAuthorities {
        require(_pool != address(0), "zero addr");
        earlyWithdrawTaxPool = _pool;
    }

    /**
        @notice set new lpstaking entities limit
        @param _newLimit new limit
    */
    function setLPStakingEntitiesLimit(uint256 _newLimit) external onlyAuthorities {
        require(_newLimit > 0, "limit must be positive");
        lpStakingEntitiesLimit = _newLimit;
    }

    /**
        @notice add new pool to stake LP
        @param _token address of LP token
        @param _totalDistribute total distribution in 0xB for this pool
        @param _startTime timestamp to start pool
        @param _duration duration of pool
    */
    function addPool(
        string memory _name,
        address _token,
        uint256 _totalDistribute,
        uint256 _startTime,
        uint256 _duration
    ) external onlyAuthorities {
        require(_startTime >= block.timestamp, "start time should be in the future");
        IERC20(token0xBAddress).transferFrom(msg.sender, address(this), _totalDistribute);
        pools.push(
            PoolInfo({
                name: _name,
                lpToken: IERC20(_token),
                totalDistribute: _totalDistribute,
                startTime: _startTime,
                duration: _duration,
                acc0xBPerShare: 0,
                lpAmountInPool: 0,
                lastRewardTimestamp: _startTime
            })
        );
    }

    // ----- Public WRITE functions -----
    /**
        @notice deposit _amount of lp to the pool with index _poolId to start new entity of staking
        @dev add new entity to control staking timestamp and taxes, never add token to older entities.
        Set rewardDebt to amount of reward currently.
        @param _poolId index of one pool
        @param _amount amount to stake
    */
    function deposit(uint32 _poolId, uint256 _amount) external {
        require(_poolId < pools.length, "wrong id");
        require(_amount > 0, "please stake");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        require(user.size < lpStakingEntitiesLimit, "too many entities, please withdraw some");
        PoolInfo storage pool = pools[_poolId];
        require(isPoolActive(pool), "pool inactive");
        updatePool(_poolId);
        pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
        pool.lpAmountInPool = pool.lpAmountInPool + _amount;
        user.entities[uint8(user.size)] = LPStakeEntity({
            amount: _amount,
            rewardDebt: (_amount * pool.acc0xBPerShare) / ONE_LP,
            creationTime: block.timestamp,
            withdrawn: 0
        });
        user.size = user.size + 1;
    }

    /**
        @notice withdraw all tokens from some entity.
        @dev same as withdraw, relocations of entities from an user is required
        @param _poolId index of pool
        @param _entityIndices indices of entities to withdraw
    */
    function withdraw(uint32 _poolId, uint8[] memory _entityIndices) public {
        require(_poolId < pools.length, "wrong id");
        for (uint256 i = 0; i < _entityIndices.length; i++) {
            require(withdrawable(_poolId, msg.sender, _entityIndices[i]), "entity in withdrawal timeout");
            require(_entityIndices[i] < userInfo[_poolId][msg.sender].size, "wrong index");
        }
        address sender = msg.sender;

        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        updatePool(_poolId);
        PoolInfo storage pool = pools[_poolId];
        uint256 totalPendingReward = 0;
        uint256 totalTax = 0;
        uint256 totalWithdrawn = 0;
        uint256 newReward;
        uint256 _amount;

        for (uint256 i = 0; i < _entityIndices.length; i++) {
            LPStakeEntity storage entity = user.entities[_entityIndices[i]];
            _amount = entity.amount;
            newReward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
            totalPendingReward += newReward;
            totalTax += (_amount * taxOfEntity(_poolId, sender, _entityIndices[i])) / HUNDRED_PERCENT;
            totalWithdrawn += _amount;
            entity.rewardDebt = entity.rewardDebt + newReward;
            entity.amount = entity.amount - _amount;
            entity.withdrawn = entity.withdrawn + _amount;
        }

        // transfer reward
        IERC20(token0xBAddress).transfer(sender, totalPendingReward);

        // transfer lp tokens
        (totalTax > 0) ? pool.lpToken.transfer(earlyWithdrawTaxPool, totalTax) : false;
        pool.lpToken.transfer(sender, totalWithdrawn - totalTax);
        pool.lpAmountInPool = pool.lpAmountInPool - totalWithdrawn;

        // refactor user storage using O(n) two-pointer algorithm
        uint8 ptrLeft = 0;
        uint8 ptrRight = user.size - 1;
        LPStakeEntity memory _entity;
        while (true) {
            while (ptrLeft < user.size && user.entities[ptrLeft].amount > 0) {
                ptrLeft++;
            }
            while (user.entities[ptrRight].amount == 0) {
                if (ptrRight == 0) break;
                ptrRight--;
            }
            if (ptrLeft >= ptrRight) break;
            _entity = user.entities[ptrRight];
            user.entities[ptrLeft] = _entity;
            ptrLeft++;
            ptrRight--;
        }
        user.size = (user.entities[ptrRight].amount == 0) ? 0 : ptrRight + 1;
    }

    /**
        @notice withdraw all entities of an user.
        @dev call withdraw() with second params being all withdraw.
        @param _poolId index of pool
    */
    function withdrawAll(uint32 _poolId) external {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][msg.sender];
        uint8[] memory indices = new uint8[](user.size);
        for (uint8 i = 0; i < user.size; i++) {
            require(withdrawable(_poolId, msg.sender, i), "entity in withdrawal timeout");
            indices[i] = i;
        }
        withdraw(_poolId, indices);
    }

    /**
        @notice claim all reward from some entities 
        @dev update reward debt and send reward to user
        @param _poolId index of pool
        @param _indices indices of entities
    */
    function claimReward(uint32 _poolId, uint8[] memory _indices) public {
        require(_poolId < pools.length, "wrong id");
        PoolInfo storage pool = pools[_poolId];
        require(isPoolClaimable(pool), "pool has not started yet");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        updatePool(_poolId);

        uint256 totalReward = 0;
        uint256 reward;

        for (uint8 i = 0; i < _indices.length; i++) {
            uint8 index = _indices[i];
            LPStakeEntity storage entity = user.entities[index];
            reward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
            totalReward += reward;
            entity.rewardDebt = entity.rewardDebt + reward;
        }
        IERC20(token0xBAddress).transfer(sender, totalReward);
    }

    /**
        @notice claim all reward from all entity of pool
        @dev update reward debt and send reward to user
        @param _poolId index of pool
    */
    function claimAllReward(uint32 _poolId) external {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][msg.sender];
        uint8[] memory indices = new uint8[](user.size);
        for (uint8 i = 0; i < user.size; i++) {
            indices[i] = i;
        }
        claimReward(_poolId, indices);
    }

    /**
        @notice update data in a lp staking pool
        @dev update accumulated reward per share of a pool for sake of reward optimization
        @param _poolId index of pool
    */
    function updatePool(uint32 _poolId) public {
        PoolInfo storage pool = pools[_poolId];
        if (block.timestamp <= pool.lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = pool.lpAmountInPool;
        if (lpSupply == 0) {
            pool.lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 rewardSinceLastChange = getDelta(pool.lastRewardTimestamp, block.timestamp) *
            getCurrentRewardPerLPPerSecond(pool);
        pool.acc0xBPerShare = pool.acc0xBPerShare + rewardSinceLastChange;
        pool.lastRewardTimestamp = block.timestamp;
    }

    // ----- Private/Internal Helpers -----
    /// @notice get time different from _from to _to
    function getDelta(uint256 _from, uint256 _to) internal pure returns (uint256) {
        return _to - _from;
    }

    /// @notice get current reward per LP per second
    function getCurrentRewardPerLPPerSecond(PoolInfo memory _pi) internal pure returns (uint256) {
        return (_pi.totalDistribute * uint256(ONE_LP)) / _pi.duration / _pi.lpAmountInPool;
    }

    /// @notice true if able to start claiming from pool
    function isPoolClaimable(PoolInfo memory _pi) internal view returns (bool) {
        return (block.timestamp >= _pi.startTime);
    }

    /// @notice true if pool is active
    function isPoolActive(PoolInfo memory _pi) internal view returns (bool) {
        return (isPoolClaimable(_pi) && block.timestamp <= _pi.startTime + _pi.duration);
    }

    /// @notice convert uint to string
    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /// @notice convert address to human-readable ascii
    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(x)) / (2**(8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    /// @notice convert bytes1 to char
    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
