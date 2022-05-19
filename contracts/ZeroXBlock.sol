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

    // ***** Storage for mint auto-swapping *****
    bool public enableAutoSwapTreasury;
    bool public enableAutoSwapDevFund;
    address public usdcToken;

    // ***** (Deprecated/Removed) Anti-bot *****
    bool public antiBotEnabled;
    uint256 public launchBuyLimit;
    uint256 public launchBuyTimeout;
    mapping(address => uint256) public _lastBuyOnLaunch;

    // ***** Blacklist storage *****
    mapping(address => bool) public _isBlacklisted;

    // ***** (Deprecated/Removed) Market makers pairs *****
    mapping(address => bool) public automatedMarketMakerPairs;

    // ***** Enable Cashout *****
    bool public enableCashout;
    bool public enableMintConts;

    // ***** V2 new storages *****
    address public cashoutTaxPool;
    LiquidityRouter public _liqRouter;
    bool public enableAutoSwapCashout;

    // ***** Sell tax storage *****
    address public sellTaxTargetAddress;
    uint256 public sellTax;
    mapping(address => bool) public _isSellTaxWhitelisted;

    // ***** Customs errors *****
    error InvalidSellTax(uint256 _sellTax);
    error InvalidAddress(address _address);

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

        sellTaxTargetAddress = msg.sender;
    }

    // ***** WRITE functions for admin *****
    /**
        @notice set address of usdc
        @param newAddress new usdc address
    */
    function setUSDCAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "NEW_USDC: zero addr");
        usdcToken = newAddress;
    }

    /**
        @notice set if user can cashout
        @param _enableCashout true if user can cashout after this tx. false if otherwise
    */
    function setEnableCashout(bool _enableCashout) external onlyOwner {
        enableCashout = _enableCashout;
    }

    /**
        @notice set if user can mint new contract
        @param value true if user can mint new contracts
    */
    function setEnableMintConts(bool value) external onlyOwner {
        enableMintConts = value;
    }

    /**
        @notice set new address of ContRewardManager
        @param crm address of the new CRM
    */
    function setContManagement(address crm) external onlyOwner {
        require(crm != address(0), "NEW_CRM: zero addr");
        _crm = CONTRewardManagement(crm);
    }

    /**
        @notice set new address of LiquidityRouter
        @param liqRouter new address of LiquidityRouter
    */
    function setLiquidityRouter(address payable liqRouter) external onlyOwner {
        require(liqRouter != address(0), "NEW_LROUTER: zero addr");
        _liqRouter = LiquidityRouter(liqRouter);
    }

    /**
        @notice set new pool to send cashout tax to
        @param wall new target address for cashout tax
    */
    function updateCashoutTaxPool(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        cashoutTaxPool = wall;
    }

    /**
        @notice set new wallet for development/marketing team
        @param wall new wallet address
    */
    function updateDevelopmentFundWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        developmentFundPool = wall;
    }

    /**
        @notice set new wallet for liquidity temporary pool
        @param wall new wallet address
    */
    function updateLiquidityWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        liquidityPool = wall;
    }

    /**
        @notice set new wallet for rewards
        @param wall new wallet address
    */
    function updateRewardsWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        rewardsPool = wall;
    }

    /**
        @notice set new wallet for treasury
        @param wall new wallet address
    */
    function updateTreasuryWallet(address payable wall) external onlyOwner {
        require(wall != address(0), "UPD_WALL: zero addr");
        treasuryPool = wall;
    }

    /**
        @notice set percentage of contract mint to be sent to rewards pool
        @param value new percentage (100 = 100%)
    */
    function updateRewardsFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = liquidityPoolFee + developmentFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        rewardsFee = value;
        totalFees = newTotalFee;
    }

    /**
        @notice set percentage of contract mint to be sent to liquidity
        @param value new percentage (100 = 100%)
    */
    function updateLiquidityFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + developmentFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        liquidityPoolFee = value;
        totalFees = newTotalFee;
    }

    /**
        @notice set percentage of contract mint to be sent to dev/marketing pool
        @param value new percentage (100 = 100%)
    */
    function updateDevelopmentFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + liquidityPoolFee + treasuryFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        developmentFee = value;
        totalFees = newTotalFee;
    }

    /**
        @notice set percentage of contract mint to be sent to treasury pool
        @param value new percentage (100 = 100%)
    */
    function updateTreasuryFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + liquidityPoolFee + developmentFee + value;
        require(newTotalFee <= 100, "FEES: total exceeding 100%");
        treasuryFee = value;
        totalFees = newTotalFee;
    }

    /**
        @notice set percentage of contract mint to be sent to cashout wallet
        @param value new percentage (100 = 100%)
    */
    function updateCashoutFee(uint256 value) external onlyOwner {
        require(value <= 100, "FEES: cashout exceeding 100%");
        cashoutFee = value;
    }

    /**
        @notice blacklist/un-blacklist an account
        @param account account to change status
        @param value set to true if blacklisting
    */
    function setBlacklistStatus(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    /**
        @notice change autoswap mode for treasury
        @param newVal set to true if enable treasury autoswap
    */
    function changeEnableAutoSwapTreasury(bool newVal) external onlyOwner {
        enableAutoSwapTreasury = newVal;
    }

    /**
        @notice change autoswap mode for dev/fund wallet
        @param newVal set to true if enable dev/fund autoswap
    */
    function changeEnableAutoSwapDevFund(bool newVal) external onlyOwner {
        enableAutoSwapDevFund = newVal;
    }

    /**
        @notice change autoswap mode for cashout
        @param newVal set to true if enable cashout autoswap
    */
    function changeEnableAutoSwapCashout(bool newVal) external onlyOwner {
        enableAutoSwapCashout = newVal;
    }

    /**
        @notice change sell tax rate
        @param newVal new tax rate
    */
    function changeSellTaxRate(uint256 newVal) external onlyOwner {
        // sell tax rate cannot be higher than 100%
        if (newVal >= 100) {
            revert InvalidSellTax(newVal);
        }
        sellTax = newVal;
    }

    /**
        @notice whitelist/un-whitelist an account
        @param account account to change status
        @param value set to true if whitelisting
    */
    function setWhitelistStatus(address account, bool value) external onlyOwner {
        if (account == address(0)) {
            revert InvalidAddress(account);
        }
        _isSellTaxWhitelisted[account] = value;
    }

    /**
        @notice change admin address
        @param newVal new admin address
    */
    function changeSellTaxTargetAddress(address newVal) external onlyOwner {
        if (newVal == address(0)) {
            revert InvalidAddress(newVal);
        }
        sellTaxTargetAddress = newVal;
    }

    // ***** Private helpers functions *****
    /// @notice override ERC-20 transfer function to check blacklisted address and prevent malicious actions
    /// also check the whitelisted address and apply sell tax
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");
        uint256 sellTaxAmount = amount * sellTax / 100;
        if (sellTaxAmount > 0 && !_isSellTaxWhitelisted[from]) {
            super._transfer(from, sellTaxTargetAddress, sellTaxAmount);
        }
        uint256 amountWithTax = _isSellTaxWhitelisted[from] ? amount : amount - sellTaxAmount;
        super._transfer(from, to, amountWithTax);
    }

    // Send fund from sender to pool.
    // amount send will be in 0xB. Will be converted if target token is in other tokens
    // Emit Funded.
    // ** not yet supported to fund from cashout or swaps
    /// @notice fund 0xB functionality wallets
    /// @dev helper function to emit "Funded" event from contract whenever user actions fund admin's wallets
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

    /// @notice return a string according to wallet name
    function _walletName(address addr) public view returns (string memory) {
        if (addr == rewardsPool) return "rewards";
        if (addr == developmentFundPool) return "devfund";
        if (addr == treasuryPool) return "treasury";
        if (addr == liquidityPool) return "liquidity";
        return "_";
    }

    // ***** WRITE functions for public *****
    /**
        @notice swap from an exact 0xB amount to an ERC20 tokens
        @param tokenAddr output token
        @param amountIn an exact amount of input 0xB
        @param amountOutMin a minimum expected output. Will raise error if can't satisfy.
        @param wait maximum wait time
    */
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
        (, fee) = _liqRouter.swapExact0xBForToken(sender, tokenAddr, amountIn, amountOutMin, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    /**
        @notice swap from an exact 0xB amount to an ERC20 tokens
        @param tokenAddr output token
        @param amountOut an exact amount of output token
        @param amountInMax a maximum expected input. Will raise error if can't satisfy.
        @param wait maximum wait time
    */
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
        (, fee) = _liqRouter.swap0xBForExactToken(sender, tokenAddr, amountOut, amountInMax, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, address(this), fee);
    }

    /**
        @notice swap from an exact amount of erc20 token to 0xB
        @param tokenAddr input token
        @param amountIn an exact amount of input token
        @param amountOutMin a minimum expected output 0xB. Will raise error if can't satisfy.
        @param wait maximum wait time
    */
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
        (, fee) = _liqRouter.swapExactTokenFor0xB(sender, tokenAddr, amountIn, amountOutMin, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, tokenAddr, fee);
    }

    /**
        @notice swap from an erc20 token to exact amount of 0xB
        @param tokenAddr input token
        @param amountOut an exact amount of output 0xB
        @param amountInMax a maximum expected amount of input token. Will raise error if can't satisfy.
        @param wait maximum wait time
    */
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
        (, fee) = _liqRouter.swapTokenForExact0xB(sender, tokenAddr, amountOut, amountInMax, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, tokenAddr, fee);
    }

    /**
        @notice swap from an exact 0xB amount to an ERC20 tokens
        @dev set msg.value as the exact input amount of AVAX
        @param amountOutMin a minimum expected output. Will raise error if can't satisfy.
        @param wait maximum wait time
    */
    function swapExactAVAXFor0xB(uint256 amountOutMin, uint256 wait) external payable {
        address sender = msg.sender;
        uint256 amountIn = msg.value;
        uint256 fee;
        (, fee) = _liqRouter.swapExactAVAXFor0xB{ value: amountIn }(sender, amountOutMin, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, _liqRouter.wrappedNative(), fee);
    }

    /**
        @notice swap from an exact 0xB amount to an ERC20 tokens
        @dev set msg.value as the maximum expected input amount of AVAX
        @param amountOut an exact amount of output 0xB.
        @param amountInMax set same as msg.value
        @param wait maximum wait time
    */
    function swapAVAXForExact0xB(
        uint256 amountOut,
        uint256 amountInMax,
        uint256 wait
    ) external payable {
        address sender = msg.sender;
        require(msg.value >= amountInMax, "SWAP: msg.value less than slippage");
        uint256 fee;
        (, fee) = _liqRouter.swapAVAXForExact0xB{ value: msg.value }(sender, amountOut, block.timestamp + wait);
        emit Funded(_walletName(_liqRouter.swapTaxPool()), ContType.Other, _liqRouter.wrappedNative(), fee);
    }

    /**
        @notice mint new contracts
        @dev create new contract instances, take funds from user and distribute to admin wallets according to
        SC configs.
        @param names list of names. The number of string in this list will be the count of new contracts.
        @param _cType type of new contracts.
    */
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

    /**
        @notice cashout reward from a single contract
        @dev send rewards from reward wallet to user and the tax portion to the configured cashoutTax wallet.
        @param _contIndex index of contract in list of contract of user
    */
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

    /**
        @notice cashout reward from all contracts
        @dev send rewards from reward wallet to user and the tax portion to the configured cashoutTax wallet.
    */
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
