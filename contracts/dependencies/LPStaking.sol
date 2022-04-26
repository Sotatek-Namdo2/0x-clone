// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

// todo: comment code
// todo: write more READ fn

contract LPStaking is Initializable, PaymentSplitterUpgradeable {
    uint256 private constant HUNDRED_PERCENT = 100_000_000;
    uint256 private constant DAY = 86400;
    uint256 private constant ONE_LP = 1e18;

    // ----- Structs -----
    struct LPStakeEntity {
        uint256 amount;
        uint256 rewardDebt;
        uint256 startTimestamp;
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
    uint256 public withdrawTimeout;
    uint256 public withdrawTaxPeriod;

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
        withdrawTaxPeriod = DAY * 30;
    }

    // ----- Events -----

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token0xBAddress || msg.sender == admin0xB || isWhitelisted(msg.sender), "Access Denied!");
        _;
    }

    // ----- External READ functions -----
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
            startTimestamp: block.timestamp
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
        // todo: taxing
        entity.rewardDebt = entity.rewardDebt + reward;

        pool.lpToken.transferFrom(address(this), address(msg.sender), _amount);
        pool.lpAmountInPool = pool.lpAmountInPool - _amount;

        // swap from last place to current entity
        if (_amount == entity.amount) {
            user.size = user.size - 1;
            user.entities[uint8(_index)] = user.entities[uint8(user.size)];
        } else {
            entity.amount = entity.amount - _amount;
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
        // todo: taxing
        uint256 reward = (entity.amount * pool.acc0xBPerShare) / ONE_LP - entity.rewardDebt;
        IERC20(token0xBAddress).transfer(sender, reward);
        entity.rewardDebt = entity.rewardDebt + reward;
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
}
