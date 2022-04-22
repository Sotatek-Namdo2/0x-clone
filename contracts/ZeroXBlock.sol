// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./interfaces/IJoeRouter02.sol";
import "./interfaces/IJoeFactory.sol";
import "./dependencies/CONTRewardManagement.sol";
import "./dependencies/LiquidityRouter.sol";

contract ZeroXBlock is Initializable, ERC20Upgradeable, OwnableUpgradeable, PaymentSplitterUpgradeable {
    CONTRewardManagement public _crm;

    IJoeRouter02 public uniswapV2Router;
    uint256 private constant HUNDRED_PERCENT = 100_000_000;

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
    uint256 public launchBuyLimit;
    uint256 public launchBuyTimeout;
    mapping(address => uint256) public _lastBuyOnLaunch;

    // ***** Blacklist storage *****
    mapping(address => bool) public _isBlacklisted;

    // ***** Market makers pairs *****
    mapping(address => bool) public automatedMarketMakerPairs;

    // ***** Enable Cashout *****
    bool public enableCashout;
    bool public enableMintConts;

    // ***** V2 new storages *****
    address public cashoutTaxPool;
    LiquidityRouter public _liqRouter;
    bool public enableAutoSwapCashout;

    // ***** Events *****
    event ContsMinted(address sender, ContType cType, uint256 contsCount);
    event RewardCashoutOne(address sender, uint256 index, uint256 amount, ContType cType);
    event RewardCashoutAll(
        address sender,
        uint256 amount,
        uint256 squareAmount,
        uint256 cubeAmount,
        uint256 tessAmount
    );
    event Funded(string walletName, ContType cType, address token, uint256 amount);

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

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 1e24, "TTL SUPPLY DIFF 1 MIL");

        require(
            addresses[1] != address(0) &&
                addresses[2] != address(0) &&
                addresses[3] != address(0) &&
                addresses[4] != address(0),
            "POOL ZERO FOUND"
        );
        require(addresses.length == balances.length, "ADDR & BALANCE ERROR");

        require(fees[0] > 0 && fees[1] > 0 && fees[2] > 0 && fees[3] > 0 && fees[4] > 0, "0% FEES FOUND");
        developmentFundPool = addresses[1];
        liquidityPool = addresses[2];
        treasuryPool = addresses[3];
        rewardsPool = addresses[4];

        cashoutTaxPool = rewardsPool;
        developmentFee = fees[0];
        treasuryFee = fees[1];
        rewardsFee = fees[2];
        liquidityPoolFee = fees[3];
        cashoutFee = fees[4];

        totalFees = rewardsFee + liquidityPoolFee + developmentFee + treasuryFee;

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
        require(newAddress != address(0), "NEW_USDC: zero addr");
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

    function setLiquidityRouter(address payable liqRouter) external onlyOwner {
        require(liqRouter != address(0), "NEW_LROUTER: zero addr");
        _liqRouter = LiquidityRouter(liqRouter);
    }

    function updateCashoutTaxPool(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        cashoutTaxPool = wall;
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

    function setBlacklistStatus(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function changeEnableAutoSwapTreasury(bool newVal) external onlyOwner {
        enableAutoSwapTreasury = newVal;
    }

    function changeEnableAutoSwapDevFund(bool newVal) external onlyOwner {
        enableAutoSwapDevFund = newVal;
    }

    function changeEnableAutoSwapCashout(bool newVal) external onlyOwner {
        enableAutoSwapCashout = newVal;
    }

    function rescueMissentToken(address userAddr, uint256 tokens) external onlyOwner {
        require(tokens <= balanceOf(address(this)), "SAVE_MISSENT: tokens exceed addr balance");
        require(userAddr != address(0), "SAVE_MISSENT: zero_address");
        _transfer(address(this), userAddr, tokens);
    }

    // ***** Private helpers functions *****
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");

        super._transfer(from, to, amount);
    }

    // Send fund from sender to pool.
    // amount send will be in 0xB. Will be converted if target token is in other tokens
    // Emit Funded.
    // ** not yet supported to fund from cashout or swaps
    function _fund(
        address sender,
        address targetWalletAddress,
        ContType cType,
        address token,
        uint256 amount
    ) private {
        string memory targetWalletName = _walletName(targetWalletAddress);
        if (token == address(this)) {
            _transfer(sender, targetWalletAddress, amount);
            emit Funded(targetWalletName, cType, token, amount);
        } else {
            _transfer(sender, address(_liqRouter), amount);
            uint256 amountOut = _liqRouter.swapExact0xBForTokenNoFee(targetWalletAddress, token, amount);
            emit Funded(targetWalletName, cType, token, amountOut);
        }
    }

    function _walletName(address addr) public view returns (string memory) {
        if (addr == rewardsPool) return "rewards";
        if (addr == developmentFundPool) return "devfund";
        if (addr == treasuryPool) return "treasury";
        if (addr == liquidityPool) return "liquidity";
        return "_";
    }

    // ***** WRITE functions for public *****
    function swapExact0xBForToken(
        address tokenAddr,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 wait
    ) public {
        address sender = msg.sender;
        require(balanceOf(sender) >= amountIn, "SWAP: insufficient balance");
        _transfer(sender, address(_liqRouter), amountIn);
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swapExact0xBForToken(
            sender,
            tokenAddr,
            amountIn,
            amountOutMin,
            block.timestamp + wait
        );
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    function swap0xBForExactToken(
        address tokenAddr,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 wait
    ) public {
        address sender = msg.sender;
        require(balanceOf(sender) >= amountInMax, "SWAP: insufficient balance");
        _transfer(sender, address(_liqRouter), amountInMax);
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swap0xBForExactToken(
            sender,
            tokenAddr,
            amountOut,
            amountInMax,
            block.timestamp + wait
        );
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    function swapExactTokenFor0xB(
        address tokenAddr,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 wait
    ) public {
        address sender = msg.sender;
        IERC20 targetToken = IERC20(tokenAddr);
        require(targetToken.balanceOf(sender) >= amountIn, "SWAP: insufficient balance");
        targetToken.transferFrom(sender, address(_liqRouter), amountIn);
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swapExactTokenFor0xB(
            sender,
            tokenAddr,
            amountIn,
            amountOutMin,
            block.timestamp + wait
        );
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    function swapTokenForExact0xB(
        address tokenAddr,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 wait
    ) public {
        address sender = msg.sender;
        IERC20 targetToken = IERC20(tokenAddr);
        require(targetToken.balanceOf(sender) >= amountInMax, "SWAP: insufficient balance");
        targetToken.transferFrom(sender, address(_liqRouter), amountInMax);
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swapTokenForExact0xB(
            sender,
            tokenAddr,
            amountOut,
            amountInMax,
            block.timestamp + wait
        );
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    function swapExactAVAXFor0xB(uint256 amountOutMin, uint256 wait) external payable {
        address sender = msg.sender;
        uint256 amountIn = msg.value;
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swapExactAVAXFor0xB{ value: amountIn }(sender, amountOutMin, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    function swapAVAXForExact0xB(
        uint256 amountOut,
        uint256 amountInMax,
        uint256 wait
    ) external payable {
        address sender = msg.sender;
        require(msg.value >= amountInMax, "SWAP: msg.value less than slippage");
        uint256 fee;
        uint256 result;
        (result, fee) = _liqRouter.swapAVAXForExact0xB{ value: msg.value }(sender, amountOut, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
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
        uint256 contCount = _crm._getContNumberOf(sender);
        require(contCount + names.length <= ownedContsLimit, "CONTMINT: reached mint limit");
        uint256 contsPrice = _crm.contPrice(_cType) * names.length;
        totalTokensPaidForMinting += contsPrice;
        require(balanceOf(sender) >= contsPrice, "CONTMINT: Balance too low for creation.");

        // DEV FUND
        uint256 developmentFundTokens = (contsPrice * developmentFee) / 100;
        if (enableAutoSwapDevFund) {
            _fund(sender, developmentFundPool, _cType, usdcToken, developmentFundTokens);
        } else {
            _fund(sender, developmentFundPool, _cType, address(this), developmentFundTokens);
        }

        // REWARDS POOL
        uint256 rewardsPoolTokens = (contsPrice * rewardsFee) / 100;
        _fund(sender, rewardsPool, _cType, address(this), rewardsPoolTokens);

        // TREASURY
        uint256 treasuryPoolTokens = (contsPrice * treasuryFee) / 100;
        if (enableAutoSwapTreasury) {
            _fund(sender, treasuryPool, _cType, usdcToken, treasuryPoolTokens);
        } else {
            _fund(sender, treasuryPool, _cType, address(this), treasuryPoolTokens);
        }

        // LIQUIDITY
        uint256 liquidityTokens = (contsPrice * liquidityPoolFee) / 100;
        _fund(sender, liquidityPool, _cType, address(this), liquidityTokens);

        // EXTRA
        uint256 extraT = contsPrice - developmentFundTokens - rewardsPoolTokens - treasuryPoolTokens - liquidityTokens;
        if (extraT > 0) {
            super._transfer(sender, address(this), extraT);
        }

        _crm.createConts(sender, names, _cType);
        emit ContsMinted(sender, _cType, names.length);
    }

    function cashoutReward(uint256 _contIndex) external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHT: Cashout Disabled");
        require(sender != address(0), "CSHT: zero address");
        require(!_isBlacklisted[sender], "CSHT: blacklisted");
        uint256 rewardAmount = _crm._getRewardAmountOfIndex(sender, _contIndex);
        require(rewardAmount > 0, "CSHT: reward not ready");

        uint256 feeAmount = 0;
        rewardAmount -= feeAmount;
        _transfer(rewardsPool, sender, rewardAmount);
        uint256 rw;
        ContType _cType;
        (rw, _cType) = _crm._cashoutContReward(sender, _contIndex);

        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            if (enableAutoSwapCashout) {
                _fund(rewardsPool, cashoutTaxPool, _cType, usdcToken, feeAmount);
            } else if (cashoutTaxPool != rewardsPool) {
                _fund(rewardsPool, cashoutTaxPool, _cType, address(this), feeAmount);
            } else {
                emit Funded("rewards", _cType, address(this), feeAmount);
            }
        }

        emit RewardCashoutOne(sender, _contIndex, rewardAmount, _cType);
    }

    function cashoutAll() external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHTALL: cashout disabled");
        require(sender != address(0), "CSHTALL: zero address");
        require(!_isBlacklisted[sender], "CSHTALL: blacklisted address");
        uint256 rewardAmount = _crm._getRewardAmountOf(sender);
        require(rewardAmount > 0, "CSHTALL: reward not ready");
        uint256 squareTotal;
        uint256 cubeTotal;
        uint256 tessTotal;
        (rewardAmount, squareTotal, cubeTotal, tessTotal) = _crm._cashoutAllContsReward(sender);

        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            if (enableAutoSwapCashout) {
                // crazy gas fee, might have to check and optimize
                _fund(rewardsPool, cashoutTaxPool, ContType.Square, usdcToken, (squareTotal * cashoutFee) / 100);
                _fund(rewardsPool, cashoutTaxPool, ContType.Cube, usdcToken, (cubeTotal * cashoutFee) / 100);
                _fund(rewardsPool, cashoutTaxPool, ContType.Tesseract, usdcToken, (tessTotal * cashoutFee) / 100);
            } else if (cashoutTaxPool != rewardsPool) {
                _fund(rewardsPool, cashoutTaxPool, ContType.Square, address(this), (squareTotal * cashoutFee) / 100);
                _fund(rewardsPool, cashoutTaxPool, ContType.Cube, address(this), (cubeTotal * cashoutFee) / 100);
                _fund(rewardsPool, cashoutTaxPool, ContType.Tesseract, address(this), (tessTotal * cashoutFee) / 100);
            } else {
                emit Funded("rewards", ContType.Square, address(this), (squareTotal * cashoutFee) / 100);
                emit Funded("rewards", ContType.Cube, address(this), (cubeTotal * cashoutFee) / 100);
                emit Funded("rewards", ContType.Tesseract, address(this), (tessTotal * cashoutFee) / 100);
            }
            squareTotal = (squareTotal * (100 - cashoutFee)) / 100;
            cubeTotal = (cubeTotal * (100 - cashoutFee)) / 100;
            tessTotal = (tessTotal * (100 - cashoutFee)) / 100;
        }
        rewardAmount -= feeAmount;
        _transfer(rewardsPool, sender, rewardAmount);
        emit RewardCashoutAll(sender, rewardAmount, squareTotal, cubeTotal, tessTotal);
    }

    // ***** READ function for public *****
}
