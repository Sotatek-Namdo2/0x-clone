// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "./dependencies/CONTRewardManagement.sol";
import "./interfaces/IJoeRouter02.sol";
import "./interfaces/IJoeFactory.sol";

contract ZeroXBlocksV1 is Initializable, ERC20Upgradeable, OwnableUpgradeable, PaymentSplitterUpgradeable {
    CONTRewardManagement public _crm;

    IJoeRouter02 public uniswapV2Router;

    uint256 private constant HUNDRED_PERCENT = 100_000_000;
    uint256 private constant LAUNCH_BUY_LIMIT = 100e18;

    uint256 public ownedContsLimit;
    uint256 private mintContLimit;

    address public uniswapV2Pair;

    uint256 public totalTokensPaidForMinting;

    // ***** Pools Address *****
    address public developmentFundPool;
    address public treasuryPool;
    address public rewardsPool;
    address public liquidityPool;

    // ***** Storage for fees *****
    uint256 public rewardsFee;
    uint256 public treasuryFee;
    uint256 public liquidityPoolFee;
    uint256 public developmentFee;
    uint256 public totalFees;
    uint256 public cashoutFee;

    // ***** Storage for swapping *****
    bool public enableAutoSwapTreasury;
    bool public enableAutoSwapDevFund;
    address public usdcToken;

    // ***** Anti-bot *****
    bool public antiBotEnabled;
    mapping(address => uint256) public _lastBuyOnLaunch;

    // ***** Blacklist storage *****
    mapping(address => bool) public _isBlacklisted;

    // ***** Market makers pairs *****
    mapping(address => bool) public automatedMarketMakerPairs;

    // ***** Enable Cashout *****
    bool public enableCashout;
    bool public enableMintConts;

    // ***** Events *****
    event ContsMinted(address sender);
    event RewardCashoutOne(address sender, uint256 index);
    event RewardCashoutAll(address sender);

    // ***** Constructor *****
    function initialize(
        address[] memory payees,
        uint256[] memory shares,
        address[] memory addresses,
        uint256[] memory balances,
        uint256[] memory fees,
        address uniV2Router,
        address usdcAddr
    ) public initializer {
        require(addresses.length > 0 && balances.length > 0, "ADDR & BALANCE ERROR");

        __Ownable_init();
        __ERC20_init("0xBlocks v1", "0XB");
        __PaymentSplitter_init(payees, shares);

        require(
            addresses[1] != address(0) &&
                addresses[2] != address(0) &&
                addresses[3] != address(0) &&
                addresses[4] != address(0),
            "POOL ZERO FOUND"
        );
        antiBotEnabled = false;

        developmentFundPool = addresses[1];
        liquidityPool = addresses[2];
        treasuryPool = addresses[3];
        rewardsPool = addresses[4];

        require(uniV2Router != address(0), "ROUTER ZERO");
        IJoeRouter02 _uniswapV2Router = IJoeRouter02(uniV2Router);

        address _uniswapV2Pair = IJoeFactory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WAVAX()
        );

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        require(fees[0] > 0 && fees[1] > 0 && fees[2] > 0 && fees[3] > 0 && fees[4] > 0, "0% FEES FOUND");
        developmentFee = fees[0];
        treasuryFee = fees[1];
        rewardsFee = fees[2];
        liquidityPoolFee = fees[3];
        cashoutFee = fees[4];

        totalFees = rewardsFee + liquidityPoolFee + developmentFee + treasuryFee;

        require(addresses.length == balances.length, "ADDR & BALANCE ERROR");

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 1012345e18, "TTL SUPPLY DIFF 1 MIL");

        usdcToken = usdcAddr;
        ownedContsLimit = 100;
        mintContLimit = 10;
        enableAutoSwapTreasury = true;
        enableAutoSwapDevFund = true;
        enableMintConts = true;
        enableCashout = true;

        antiBotEnabled = true;
    }

    // ***** WRITE functions for admin *****
    function setUSDCAddress(address newAddress) external onlyOwner {
        usdcToken = newAddress;
    }

    function setEnableAntiBot(bool _enable) external onlyOwner {
        antiBotEnabled = _enable;
    }

    function setEnableCashout(bool _enableCashout) external onlyOwner {
        enableCashout = _enableCashout;
    }

    function setEnableMintConts(bool value) external onlyOwner {
        enableMintConts = value;
    }

    function setContManagement(address crm) external onlyOwner {
        require(crm != address(0), "NEW_CRM: zero addr");
        _crm = CONTRewardManagement(crm);
    }

    function changeContPrice(ContType _cType, uint256 newPrice) external onlyOwner {
        _crm._changeContPrice(_cType, newPrice);
    }

    function changeRewardAPRPerCont(ContType _cType, int256 deductPcent) external onlyOwner {
        require(deductPcent < int256(HUNDRED_PERCENT), "REDUCE_RWD: do not reduce more than 100%");
        _crm._changeRewardAPRPerCont(_cType, deductPcent);
    }

    function changeCashoutTimeout(uint256 newTime) external onlyOwner {
        _crm._changeCashoutTimeout(newTime);
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router), "TKN: The router already has that address");
        uniswapV2Router = IJoeRouter02(newAddress);
        address _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WAVAX()
        );
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateDevelopmentFundWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        developmentFundPool = wall;
    }

    function updateLiquidityWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        liquidityPool = wall;
    }

    function updateRewardsWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        rewardsPool = wall;
    }

    function updateTreasuryWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        treasuryPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = liquidityPoolFee + developmentFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        rewardsFee = value;
        totalFees = newTotalFee;
    }

    function updateLiquidityFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + developmentFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        liquidityPoolFee = value;
        totalFees = newTotalFee;
    }

    function updateDevelopmentFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + liquidityPoolFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        developmentFee = value;
        totalFees = newTotalFee;
    }

    function updateTreasuryFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + liquidityPoolFee + developmentFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        treasuryFee = value;
        totalFees = newTotalFee;
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        require(value <= 100, "FEES: cashout exceeding 100%");
        cashoutFee = value;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "TKN: The PancakeSwap pair cannot be removed");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function setBlacklistStatus(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function changeEnableAutoSwapTreasury(bool newVal) external onlyOwner {
        enableAutoSwapTreasury = newVal;
    }

    function changeEnableAutoSwapDevFund(bool newVal) external onlyOwner {
        enableAutoSwapDevFund = newVal;
    }

    // ***** Private helpers functions *****
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;
    }

    function getContNumberOf(address account) private view returns (uint256) {
        return _crm._getContNumberOf(account);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");

        if (
            antiBotEnabled &&
            to != uniswapV2Pair &&
            to != rewardsPool &&
            to != treasuryPool &&
            to != liquidityPool &&
            to != developmentFundPool &&
            to != address(this)
        ) {
            require(balanceOf(to) + amount <= LAUNCH_BUY_LIMIT, "0xB LAUNCH: own exceeds limit");
            // if (_lastBuyOnLaunch[to].isValue) {
            //     require(block.timestamp - _lastBuyOnLaunch[to] >= 300, "0xB LAUNCH: timeout");
            // }
        }

        _lastBuyOnLaunch[to] = block.timestamp;
        super._transfer(from, to, amount);
    }

    function swapAVAXSendTo(address targetWallet, uint256 tokens) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WAVAX();

        _approve(address(this), address(uniswapV2Router), tokens);

        uniswapV2Router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of AVAX
            path,
            targetWallet,
            block.timestamp
        );
    }

    function swapUSDCSendTo(address targetWallet, uint256 tokens) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WAVAX();
        path[2] = usdcToken;

        _approve(address(this), address(uniswapV2Router), tokens);

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of USDC
            path,
            targetWallet,
            block.timestamp
        );
    }

    function provideLiquidity(
        address sender,
        address targetWallet,
        uint256 tokens
    ) private {
        _approve(sender, address(uniswapV2Router), tokens);
        uniswapV2Router.addLiquidityAVAX(address(this), tokens, 0, 0, targetWallet, (block.timestamp + 120) * 1000);
    }

    // ***** WRITE functions for public *****
    function mintConts(string[] memory names, ContType _cType) external {
        require(enableMintConts, "CONTMINT: mint conts disabled");
        require(names.length <= mintContLimit, "CONTMINT: too many conts");
        for (uint256 i = 0; i < names.length; i++) {
            require(bytes(names[i]).length > 3 && bytes(names[i]).length < 33, "CONTMINT: improper character count");
        }

        address sender = _msgSender();
        require(sender != address(0), "CONTMINT: zero address");
        require(!_isBlacklisted[sender], "CONTMINT: blacklisted address");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "CONTMINT: pools cannot create cont"
        );
        uint256 contCount = getContNumberOf(sender);
        require(contCount + names.length <= ownedContsLimit, "CONTMINT: reached mint limit");
        uint256 contsPrice = _crm.contPrice(_cType) * names.length;
        totalTokensPaidForMinting += contsPrice;
        require(balanceOf(sender) >= contsPrice, "CONTMINT: Balance too low for creation.");

        // DEV FUND
        uint256 developmentFundTokens = (contsPrice * developmentFee) / 100;
        if (enableAutoSwapDevFund) {
            super._transfer(sender, address(this), developmentFundTokens);
            swapUSDCSendTo(developmentFundPool, developmentFundTokens);
        } else {
            super._transfer(sender, developmentFundPool, developmentFundTokens);
        }

        // REWARDS POOL
        uint256 rewardsPoolTokens = (contsPrice * rewardsFee) / 100;
        super._transfer(sender, rewardsPool, rewardsPoolTokens);

        // TREASURY
        uint256 treasuryPoolTokens = (contsPrice * treasuryFee) / 100;
        if (enableAutoSwapTreasury) {
            super._transfer(sender, address(this), treasuryPoolTokens);
            swapUSDCSendTo(treasuryPool, treasuryPoolTokens);
        } else {
            super._transfer(sender, treasuryPool, treasuryPoolTokens);
        }

        // LIQUIDITY
        uint256 liquidityTokens = (contsPrice * liquidityPoolFee) / 100;
        provideLiquidity(sender, liquidityPool, liquidityTokens);

        // EXTRA
        uint256 extraT = contsPrice - developmentFundTokens - rewardsPoolTokens - treasuryPoolTokens - liquidityTokens;
        if (extraT > 0) {
            super._transfer(sender, address(this), extraT);
        }

        _crm.createConts(sender, names, _cType);
        emit ContsMinted(sender);
    }

    function cashoutReward(uint256 _contIndex) external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHT: Cashout Disabled");
        require(sender != address(0), "CSHT: zero address");
        require(!_isBlacklisted[sender], "CSHT: this address has been blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = _crm._getRewardAmountOf(sender, _contIndex);
        require(rewardAmount > 0, "CSHT: your reward is not ready yet");

        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            uniswapV2Router.addLiquidityAVAX(address(this), feeAmount, 0, 0, liquidityPool, block.timestamp + 360);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        _crm._cashoutContReward(sender, _contIndex);
        emit RewardCashoutOne(sender, _contIndex);
    }

    function cashoutAll() external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHTALL: cashout disabled");
        require(sender != address(0), "CSHTALL: zero address");
        require(!_isBlacklisted[sender], "CSHTALL: blacklisted address");
        require(sender != developmentFundPool && sender != rewardsPool, "CSHTALL: pools cannot cashout");
        uint256 rewardAmount = _crm._getRewardAmountOf(sender);
        require(rewardAmount > 0, "CSHTALL: reward not ready");

        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            provideLiquidity(sender, liquidityPool, feeAmount);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        _crm._cashoutAllContsReward(sender);
        emit RewardCashoutAll(sender);
    }

    // ***** READ function for public *****
    function getRewardAmount() external view returns (uint256) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getRewardAmountOf(_msgSender());
    }

    function getContPrice(ContType _cType) external view returns (uint256) {
        return _crm.contPrice(_cType);
    }

    function getRewardAPRPerCont(ContType _cType) external view returns (uint256) {
        return _crm.currentRewardAPRPerNewCont(_cType);
    }

    function getCashoutTimeout() external view returns (uint256) {
        return _crm.cashoutTimeout();
    }

    function getContsNames() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsNames(_msgSender());
    }

    function getContsCurrentAPR() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsCurrentAPR(_msgSender());
    }

    function getContsInitialAPR() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsInitialAPR(_msgSender());
    }

    function getContsCreationTime() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsCreationTime(_msgSender());
    }

    function getContsTypes() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsTypes(_msgSender());
    }

    function getContsRewards() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsRewardAvailable(_msgSender());
    }

    function getContsLastCashoutTime() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        return _crm._getContsLastUpdateTime(_msgSender());
    }

    function getTotalConts() external view returns (uint256) {
        return _crm.totalContsCreated();
    }

    function getTotalContsPerContType(ContType __cType) external view returns (uint256) {
        return _crm.totalContsPerContType(__cType);
    }
}
