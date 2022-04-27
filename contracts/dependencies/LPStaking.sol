// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

// todo: comment code

// structure:
// - My pools:
// + APR (read BA docs)

contract LPStaking is Initializable, PaymentSplitterUpgradeable {
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
        uint256 size;
        mapping(uint8 => LPStakeEntity) entities;
    }

    struct PoolInfo {
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
    mapping(uint32 => mapping(address => UserLPStakeInfo)) private userInfo;
    mapping(address => bool) private whitelistAuthorities;

    // ----- Router Addresses -----
    address public token0xBAddress;
    address public admin0xB;

    // ----- Constructor -----
    function initialize() public initializer {
        address[] memory payees = new address[](1);
        payees[0] = msg.sender;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        __PaymentSplitter_init(payees, shares);
        admin0xB = msg.sender;
        lpStakingEntitiesLimit = 100;
        withdrawTimeout = DAY;
        withdrawTaxLevel = [0, 0, DAY * 30, DAY * 60];
        withdrawTaxPortion = [5_000_000, 5_000_000, 2_500_000, 0];
        earlyWithdrawTaxPool = msg.sender;
    }

    // ----- Events -----

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token0xBAddress || msg.sender == admin0xB || isWhitelisted(msg.sender), "Access Denied!");
        _;
    }

    // ----- External READ functions -----
    function getAPR(uint32 _poolId) public view returns (uint256 apr) {
        require(_poolId < pools.length, "wrong id");
        PoolInfo memory pool = pools[_poolId];
        apr = (pool.totalDistribute * YEAR * uint256(1e18)) / pool.duration / pool.lpAmountInPool;
    }

    function totalStakeOfUser(uint32 _poolId, address addr) public view returns (uint256 totalStake) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        totalStake = 0;
        for (uint8 i = 1; i < user.size; i++) {
            totalStake += user.entities[i].amount;
        }
    }

    function getUserTimestamps(uint32 _poolId, address addr) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return "";
        }
        res = uint2str(user.entities[0].creationTime);
        for (uint8 i = 1; i < user.size; i++) {
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(user.entities[i].creationTime)));
        }
    }

    function getUserStakeAmounts(uint32 _poolId, address addr) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return "";
        }
        res = uint2str(user.entities[0].amount + user.entities[0].withdrawn);
        for (uint8 i = 1; i < user.size; i++) {
            uint256 amount = user.entities[i].amount + user.entities[i].withdrawn;
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(amount)));
        }
    }

    function getUserPendingReward(uint32 _poolId, address addr) public view returns (string memory res) {
        require(_poolId < pools.length, "wrong id");
        UserLPStakeInfo storage user = userInfo[_poolId][addr];
        if (user.size == 0) {
            return "";
        }
        res = uint2str(pendingReward(_poolId, addr, 0));
        for (uint8 i = 1; i < user.size; i++) {
            res = string(abi.encodePacked(res, SEPARATOR, uint2str(pendingReward(_poolId, addr, i))));
        }
    }

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
            uint256 reward = 0;
            acc0xBPerShare = ((acc0xBPerShare + reward) * ONE_LP) / lpSupply;
        }
        return (entity.amount * acc0xBPerShare) / ONE_LP - entity.rewardDebt;
    }

    function isWhitelisted(address addr) public view returns (bool) {
        return whitelistAuthorities[addr];
    }

    function withdrawable(
        uint32 _poolId,
        address addr,
        uint32 _index
    ) public view returns (bool) {
        require(_poolId < pools.length, "wrong id");
        LPStakeEntity memory entity = userInfo[_poolId][addr].entities[uint8(_index)];
        return (entity.creationTime + withdrawTimeout < block.timestamp);
    }

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
    function setToken(address _token) external onlyAuthorities {
        require(_token != address(0), "NEW_TOKEN: zero addr");
        token0xBAddress = _token;
    }

    function addPool(
        address _token,
        uint256 _totalDistribute,
        uint256 _startTime,
        uint256 _duration
    ) external onlyAuthorities {
        require(_startTime >= block.timestamp, "start time should be in the future");
        pools.push(
            PoolInfo({
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

    // only create new records
    function deposit(uint32 _poolId, uint256 _amount) external {
        require(_poolId < pools.length, "wrong id");
        require(_amount > 0, "please stake");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        require(user.size < lpStakingEntitiesLimit, "too many entities, please withdraw some");

        updatePool(_poolId);
        PoolInfo storage pool = pools[_poolId];
        pool.lpToken.transferFrom(address(msg.sender), address(this), _amount);
        pool.lpAmountInPool = pool.lpAmountInPool + _amount;
        user.entities[uint8(user.size)] = LPStakeEntity({
            amount: _amount,
            rewardDebt: 0,
            creationTime: block.timestamp,
            withdrawn: 0
        });
        user.size = user.size + 1;
    }

    function withdraw(
        uint32 _poolId,
        uint32 _index,
        uint32 _amount
    ) external {
        require(_poolId < pools.length, "wrong id");
        require(_amount > 0, "please unstake");
        require(withdrawable(_poolId, msg.sender, _index), "entity in withdrawal timeout");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        require(_index < user.size, "wrong index");
        require(_amount <= user.entities[uint8(_index)].amount, "amount too big");

        updatePool(_poolId);
        PoolInfo storage pool = pools[_poolId];
        LPStakeEntity storage entity = user.entities[uint8(_index)];

        // transfer 0xB reward
        uint256 reward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
        IERC20(token0xBAddress).transfer(sender, reward);
        entity.rewardDebt = entity.rewardDebt + reward;

        uint256 tax = taxOfEntity(_poolId, sender, _index);
        if (tax > 0) {
            tax = (tax * _amount) / HUNDRED_PERCENT;
            pool.lpToken.transferFrom(address(this), earlyWithdrawTaxPool, tax);
        }
        pool.lpToken.transferFrom(address(this), address(msg.sender), _amount - tax);
        pool.lpAmountInPool = pool.lpAmountInPool - _amount;

        // swap from last place to current entity
        if (_amount == entity.amount) {
            user.size = user.size - 1;
            user.entities[uint8(_index)] = user.entities[uint8(user.size)];
        } else {
            entity.amount = entity.amount - _amount;
            entity.withdrawn = entity.withdrawn + _amount;
        }
    }

    function claimReward(uint32 _poolId, uint32 _index) external {
        require(_poolId < pools.length, "wrong id");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        require(_index < user.size, "wrong index");

        updatePool(_poolId);
        LPStakeEntity storage entity = user.entities[uint8(_index)];
        PoolInfo storage pool = pools[_poolId];
        uint256 reward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
        IERC20(token0xBAddress).transfer(sender, reward);
        entity.rewardDebt = entity.rewardDebt + reward;
    }

    function claimAllReward(uint32 _poolId) external {
        require(_poolId < pools.length, "wrong id");
        address sender = msg.sender;
        UserLPStakeInfo storage user = userInfo[_poolId][sender];
        updatePool(_poolId);
        PoolInfo storage pool = pools[_poolId];

        uint256 totalReward = 0;
        uint256 reward;

        for (uint8 i = 0; i < user.size; i++) {
            LPStakeEntity storage entity = user.entities[i];
            reward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
            totalReward += reward;
            entity.rewardDebt = entity.rewardDebt + reward;
        }
        IERC20(token0xBAddress).transfer(sender, totalReward);
    }

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
    function getDelta(uint256 _from, uint256 _to) internal pure returns (uint256) {
        return _to - _from;
    }

    function getCurrentRewardPerLPPerSecond(PoolInfo memory _pi) internal pure returns (uint256) {
        return (_pi.totalDistribute * uint256(ONE_LP)) / _pi.duration / _pi.lpAmountInPool;
    }

    function isPoolClaimable(PoolInfo memory _pi) internal view returns (bool) {
        return (block.timestamp >= _pi.startTime);
    }

    function isPoolActive(PoolInfo memory _pi) internal view returns (bool) {
        return (isPoolClaimable(_pi) && block.timestamp <= _pi.startTime + _pi.duration);
    }

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
}
