// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./dependencies/CONTRewardManagement.sol";
import "./dependencies/LiquidityRouter.sol";

contract ZeroXBlock is Initializable, ERC20Upgradeable, OwnableUpgradeable, PaymentSplitterUpgradeable {
    CONTRewardManagement public _crm;
    LiquidityRouter public _liqRouter;

    uint256 private constant HUNDRED_PERCENT = 100_000_000;

    uint256 public ownedContsLimit;
    uint256 private mintContLimit;

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
    uint256 public swapFee;

    // ***** Storage for swapping *****
    bool public enableAutoSwapTreasury;
    bool public enableAutoSwapDevFund;
    address public usdcToken;

    // ***** Blacklist storage *****
    mapping(address => bool) public _isBlacklisted;

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
        address usdcAddr
    ) public initializer {
        require(addresses.length > 0 && balances.length > 0, "ADDR & BALANCE ERROR");

        __Ownable_init();
        __ERC20_init("0xBlock", "0xB");
        __PaymentSplitter_init(payees, shares);

        require(
            addresses[1] != address(0) &&
                addresses[2] != address(0) &&
                addresses[3] != address(0) &&
                addresses[4] != address(0),
            "POOL ZERO FOUND"
        );
        developmentFundPool = addresses[1];
        liquidityPool = addresses[2];
        treasuryPool = addresses[3];
        rewardsPool = addresses[4];

        require(fees[0] > 0 && fees[1] > 0 && fees[2] > 0 && fees[3] > 0 && fees[4] > 0, "0% FEES FOUND");
        developmentFee = fees[0];
        treasuryFee = fees[1];
        rewardsFee = fees[2];
        liquidityPoolFee = fees[3];
        cashoutFee = fees[4];
        swapFee = fees[5];

        totalFees = rewardsFee + liquidityPoolFee + developmentFee + treasuryFee;

        require(addresses.length == balances.length, "ADDR & BALANCE ERROR");

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 1e24, "TTL SUPPLY DIFF 1 MIL");

        usdcToken = usdcAddr;
        ownedContsLimit = 100;
        mintContLimit = 10;
        enableAutoSwapTreasury = false;
        enableAutoSwapDevFund = true;
        enableMintConts = true;
        enableCashout = true;
    }

    // ***** WRITE functions for admin *****
    function setUSDCAddress(address newAddress) external onlyOwner {
        usdcToken = newAddress;
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

    function setLiquidityRouter(address liqRouter) external onlyOwner {
        require(liqRouter != address(0), "NEW_LROUTER: zero addr");
        _liqRouter = LiquidityRouter(liqRouter);
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

    function updateSwapFee(uint256 value) external onlyOwner {
        require(value <= HUNDRED_PERCENT, "FEES: swap exceeding 100%");
        swapFee = value;
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

    function rescueMissentToken(address userAddr, uint256 tokens) external onlyOwner {
        require(tokens <= balanceOf(address(this)), "SAVE_MISSENT: tokens exceed addr balance");
        require(userAddr != address(0), "SAVE_MISSENT: zero_address");
        _transfer(address(this), userAddr, tokens);
    }

    // ***** Private helpers functions *****
    function getContNumberOf(address account) private view returns (uint256) {
        return _crm._getContNumberOf(account);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");

        super._transfer(from, to, amount);
    }

    function provideLiquidity(address sender, uint256 tokens) private {
        super._transfer(sender, liquidityPool, tokens);
    }

    // ***** WRITE functions for public *****
    function swapExact0xBForToken(
        address tokenAddr,
        uint256 amountIn,
        uint256 slippageTolerance,
        uint256 wait
    ) public {
        address sender = msg.sender;
        uint256 fee = (amountIn * swapFee) / HUNDRED_PERCENT;
        uint256[] memory amountOutCurrent = _liqRouter.getOutputAmount(false, tokenAddr, amountIn - fee);
        uint256 amountOutMin = amountOutCurrent[amountOutCurrent.length - 1];
        amountOutMin = (amountOutMin * (HUNDRED_PERCENT - slippageTolerance)) / HUNDRED_PERCENT;
        require(balanceOf(sender) >= amountIn, "SWAP: insufficient balance");
        _transfer(sender, address(_liqRouter), amountIn - fee);
        provideLiquidity(sender, fee);
        _liqRouter.swapExact0xBForToken(sender, tokenAddr, amountIn - fee, amountOutMin, block.timestamp + wait);
    }

    function swap0xBForExactToken(
        address tokenAddr,
        uint256 amountOut,
        uint256 slippageTolerance,
        uint256 wait
    ) public {
        address sender = msg.sender;
        uint256[] memory amountInCurrent = _liqRouter.getInputAmount(false, tokenAddr, amountOut);
        uint256 amountInMax = (amountInCurrent[0] * (HUNDRED_PERCENT + slippageTolerance)) / HUNDRED_PERCENT;
        uint256 fee = (amountInCurrent[0] * swapFee) / HUNDRED_PERCENT;
        require(balanceOf(sender) >= amountInMax + fee, "SWAP: insufficient balance");
        _transfer(sender, address(_liqRouter), amountInMax);
        provideLiquidity(sender, fee);
        _liqRouter.swap0xBForExactToken(sender, tokenAddr, amountOut, amountInMax, block.timestamp + wait);
    }

    function swapExactTokenFor0xB(
        address tokenAddr,
        uint256 amountIn,
        uint256 slippageTolerance,
        uint256 wait
    ) public {
        address sender = msg.sender;
        uint256 fee = (amountIn * swapFee) / HUNDRED_PERCENT;
        uint256[] memory amountOutCurrent = _liqRouter.getOutputAmount(true, tokenAddr, amountIn - fee);
        uint256 amountOutMin = amountOutCurrent[amountOutCurrent.length - 1];
        amountOutMin = (amountOutMin * (HUNDRED_PERCENT - slippageTolerance)) / HUNDRED_PERCENT;
        IERC20 targetToken = IERC20(tokenAddr);
        require(targetToken.balanceOf(sender) >= amountIn, "SWAP: insufficient balance");
        targetToken.transferFrom(sender, address(_liqRouter), amountIn - fee);
        targetToken.transferFrom(sender, liquidityPool, fee);
        _liqRouter.swapExactTokenFor0xB(sender, tokenAddr, amountIn - fee, amountOutMin, block.timestamp + wait);
    }

    function swapTokenForExact0xB(
        address tokenAddr,
        uint256 amountOut,
        uint256 slippageTolerance,
        uint256 wait
    ) public {
        address sender = msg.sender;
        uint256[] memory amountInCurrent = _liqRouter.getInputAmount(true, tokenAddr, amountOut);
        uint256 amountInMax = (amountInCurrent[0] * (HUNDRED_PERCENT + slippageTolerance)) / HUNDRED_PERCENT;
        IERC20 targetToken = IERC20(tokenAddr);
        uint256 fee = (amountInCurrent[0] * swapFee) / HUNDRED_PERCENT;
        require(targetToken.balanceOf(sender) >= amountInMax + fee, "SWAP: insufficient balance");
        targetToken.transferFrom(sender, address(_liqRouter), amountInMax);
        targetToken.transferFrom(sender, liquidityPool, fee);
        _liqRouter.swapTokenForExact0xB(sender, tokenAddr, amountOut, amountInMax, block.timestamp + wait);
    }

    function swapExactAVAXFor0xB(uint256 slippageTolerance, uint256 wait) external payable {
        address sender = msg.sender;
        uint256 amountIn = msg.value;
        uint256 fee = (amountIn * swapFee) / HUNDRED_PERCENT;
        uint256[] memory amountOutCurrent = _liqRouter.getOutputAmount(
            true,
            _liqRouter.wrappedNative(),
            amountIn - fee
        );
        uint256 amountOutMin = amountOutCurrent[amountOutCurrent.length - 1];
        amountOutMin = (amountOutMin * (HUNDRED_PERCENT - slippageTolerance)) / HUNDRED_PERCENT;
        payable(liquidityPool).transfer(fee);
        _liqRouter.swapExactAVAXFor0xB{ value: amountIn - fee }(sender, amountOutMin, block.timestamp + wait);
    }

    function swapAVAXForExact0xB(
        uint256 amountOut,
        uint256 slippageTolerance,
        uint256 wait
    ) external payable {
        address sender = msg.sender;
        uint256 amountInMaxSent = msg.value;
        uint256[] memory amountInCurrent = _liqRouter.getOutputAmount(true, _liqRouter.wrappedNative(), amountOut);
        uint256 amountInMax = amountInCurrent[0];
        amountInMax = (amountInMax * (HUNDRED_PERCENT + slippageTolerance)) / HUNDRED_PERCENT;
        uint256 fee = (amountInMax * swapFee) / HUNDRED_PERCENT;
        require(amountInMaxSent >= amountInMax, "SWAP: msg.value less than slippage");
        payable(liquidityPool).transfer(fee);
        _liqRouter.swapAVAXForExact0xB{ value: amountInMaxSent - fee }(sender, amountOut, block.timestamp + wait);
    }

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
            super._transfer(sender, address(_liqRouter), developmentFundTokens);
            _liqRouter.swapExact0xBForToken(developmentFundPool, usdcToken, developmentFundTokens, 0, block.timestamp);
        } else {
            super._transfer(sender, developmentFundPool, developmentFundTokens);
        }

        // REWARDS POOL
        uint256 rewardsPoolTokens = (contsPrice * rewardsFee) / 100;
        super._transfer(sender, rewardsPool, rewardsPoolTokens);

        // TREASURY
        uint256 treasuryPoolTokens = (contsPrice * treasuryFee) / 100;
        if (enableAutoSwapTreasury) {
            super._transfer(sender, address(_liqRouter), treasuryPoolTokens);
            _liqRouter.swapExact0xBForToken(treasuryPool, usdcToken, treasuryPoolTokens, 0, block.timestamp);
        } else {
            super._transfer(sender, treasuryPool, treasuryPoolTokens);
        }

        // LIQUIDITY
        uint256 liquidityTokens = (contsPrice * liquidityPoolFee) / 100;
        provideLiquidity(sender, liquidityTokens);

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
        require(!_isBlacklisted[sender], "CSHT: blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "CSHT: pools cannot cashout rewards"
        );
        uint256 rewardAmount = _crm._getRewardAmountOf(sender, _contIndex);
        require(rewardAmount > 0, "CSHT: reward not ready");

        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
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
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        _crm._cashoutAllContsReward(sender);
        emit RewardCashoutAll(sender);
    }

    // ***** READ function for public *****
    function getRewardAmount() external view returns (uint256) {
        return _crm._getRewardAmountOf(_msgSender());
    }

    function getContPrice(ContType _cType) external view returns (uint256) {
        return _crm.contPrice(_cType);
    }

    function getRewardAPRPerCont(ContType _cType) external view returns (uint256) {
        return _crm.currentRewardAPRPerNewCont(_cType);
    }

    function getContsNames() external view returns (string memory) {
        return _crm._getContsNames(_msgSender());
    }

    function getContsCurrentAPR() external view returns (string memory) {
        return _crm._getContsCurrentAPR(_msgSender());
    }

    function getContsInitialAPR() external view returns (string memory) {
        return _crm._getContsInitialAPR(_msgSender());
    }

    function getContsCreationTime() external view returns (string memory) {
        return _crm._getContsCreationTime(_msgSender());
    }

    function getContsTypes() external view returns (string memory) {
        return _crm._getContsTypes(_msgSender());
    }

    function getContsRewards() external view returns (string memory) {
        return _crm._getContsRewardAvailable(_msgSender());
    }

    function getContsLastCashoutTime() external view returns (string memory) {
        return _crm._getContsLastUpdateTime(_msgSender());
    }

    function totalContsPerType(ContType _ct) external view returns (uint256) {
        return _crm.totalContsPerContType(_ct);
    }

    function tokenReceivedPerType(ContType _ct) external view returns (uint256) {
        return _crm.totalContsPerContType(_ct) + uint256(_ct);
    }

    function breakevenPerType(ContType _ct) external view returns (uint256) {
        return _crm.totalContsPerContType(_ct) - uint256(_ct);
    }

    function claimedRewardsPerType(ContType _ct) external view returns (uint256) {
        return _crm.totalContsPerContType(_ct) * uint256(_ct);
    }
}
