// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "./dependencies/NODERewardManagement.sol";
import "./interfaces/IJoeRouter02.sol";
import "./interfaces/IPinkAntiBot.sol";
import "./interfaces/IJoeFactory.sol";

contract ZeroXBlocksV1 is Initializable, ERC20Upgradeable, OwnableUpgradeable, PaymentSplitterUpgradeable {
    NODERewardManagement public _nrm;

    IJoeRouter02 public uniswapV2Router;
    IPinkAntiBot public pinkAntiBot;

    uint256 public ownedNodesLimit;
    uint256 private mintNodeLimit;

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
    bool public enableAutoSwap;
    uint256 public swapTokensAmount;
    address public usdcToken;

    // ***** Blacklist storage *****
    mapping(address => bool) public _isBlacklisted;

    // ***** Market makers pairs *****
    mapping(address => bool) public automatedMarketMakerPairs;

    // ***** Enable Cashout *****
    bool public enableCashout = true;
    bool public enableMintNodes = true;

    // ***** Constructor *****
    function initialize(
        address[] memory payees,
        uint256[] memory shares,
        address[] memory addresses,
        uint256[] memory balances,
        uint256[] memory fees,
        address uniV2Router,
        address pinkAntiBot_,
        address usdcAddr
    ) public initializer {
        require(addresses.length > 0 && balances.length > 0, "ADDR & BALANCE ERROR");

        __Ownable_init();
        __ERC20_init("0xBlocks v1", "0XB");
        __PaymentSplitter_init(payees, shares);

        developmentFundPool = addresses[1];
        liquidityPool = addresses[2];
        treasuryPool = addresses[3];
        rewardsPool = addresses[4];

        require(
            developmentFundPool != address(0) &&
                liquidityPool != address(0) &&
                treasuryPool != address(0) &&
                rewardsPool != address(0),
            "POOL ZERO FOUND"
        );

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
        ownedNodesLimit = 100;
        mintNodeLimit = 10;
        enableAutoSwap = true;
        swapTokensAmount = 0;

        // Create an instance of the PinkAntiBot variable from the provided address
        pinkAntiBot = IPinkAntiBot(pinkAntiBot_);
        // Register the deployer to be the token owner with PinkAntiBot. You can
        // later change the token owner in the PinkAntiBot contract
        pinkAntiBot.setTokenOwner(msg.sender);
    }

    // ***** WRITE functions for admin *****
    function setEnableCashout(bool _enableCashout) external onlyOwner {
        enableCashout = _enableCashout;
    }

    function setEnableMintNodes(bool value) external onlyOwner {
        enableMintNodes = value;
    }

    function setNodeManagement(address nrm) external onlyOwner {
        _nrm = NODERewardManagement(nrm);
    }

    function changeNodePrice(ContractType _cType, uint256 newPrice) external onlyOwner {
        _nrm._changeNodePrice(_cType, newPrice);
    }

    function changeRewardAPRPerNode(ContractType _cType, int256 deductPcent) external onlyOwner {
        _nrm._changeRewardAPRPerNode(_cType, deductPcent);
    }

    function changeCashoutTimeout(uint256 newTime) external onlyOwner {
        _nrm._changeCashoutTimeout(newTime);
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

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateDevelopmentFundWallet(address payable wall) external onlyOwner {
        developmentFundPool = wall;
    }

    function updateLiquidityWallet(address payable wall) external onlyOwner {
        liquidityPool = wall;
    }

    function updateRewardsWallet(address payable wall) external onlyOwner {
        rewardsPool = wall;
    }

    function updateTreasuryWallet(address payable wall) external onlyOwner {
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

    function changeEnableAutoSwap(bool newVal) external onlyOwner {
        enableAutoSwap = newVal;
    }

    // ***** Private helpers functions *****
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;
    }

    function getNodeNumberOf(address account) private view returns (uint256) {
        return _nrm._getNodeNumberOf(account);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");
        pinkAntiBot.onPreTransferCheck(from, to, amount);

        super._transfer(from, to, amount);
    }

    function swapAVAXSendTo(address targetWallet, uint256 tokens) private {
        if (enableAutoSwap) {
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
        } else {
            super._transfer(address(this), targetWallet, tokens);
        }
    }

    function swapUSDCSendTo(address targetWallet, uint256 tokens) private {
        if (enableAutoSwap) {
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
        } else {
            super._transfer(address(this), targetWallet, tokens);
        }
    }

    // ***** WRITE functions for public *****
    function mintNodes(string[] memory names, ContractType _cType) external {
        require(enableMintNodes, "NODEMINT: mint nodes disabled");
        require(names.length <= mintNodeLimit, "NODEMINT: too many nodes");
        for (uint256 i = 0; i < names.length; i++) {
            require(bytes(names[i]).length > 3 && bytes(names[i]).length < 33, "NODEMINT: improper character count");
        }

        address sender = _msgSender();
        require(sender != address(0), "NODEMINT: zero address");
        require(!_isBlacklisted[sender], "NODEMINT: blacklisted address");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "NODEMINT: pools cannot create node"
        );
        uint256 nodeCount = getNodeNumberOf(sender);
        require(nodeCount + names.length <= ownedNodesLimit, "NODEMINT: reached mint limit");
        uint256 nodesPrice = _nrm.nodePrice(_cType) * names.length;
        totalTokensPaidForMinting += nodesPrice;
        require(balanceOf(sender) >= nodesPrice, "NODEMINT: Balance too low for creation.");

        // DEV FUND
        uint256 developmentFundTokens = (nodesPrice * developmentFee) / 100;
        super._transfer(sender, address(this), developmentFundTokens);
        swapUSDCSendTo(developmentFundPool, developmentFundTokens);

        // REWARDS POOL
        uint256 rewardsPoolTokens = (nodesPrice * rewardsFee) / 100;
        super._transfer(sender, rewardsPool, rewardsPoolTokens);

        // TREASURY
        uint256 treasuryPoolTokens = (nodesPrice * treasuryFee) / 100;
        super._transfer(sender, address(this), treasuryPoolTokens);
        swapUSDCSendTo(treasuryPool, treasuryPoolTokens);

        // LIQUIDITY
        uint256 liquidityTokens = (nodesPrice * liquidityPoolFee) / 100;
        super._transfer(sender, liquidityPool, liquidityTokens - liquidityTokens / 2);
        super._transfer(sender, address(this), liquidityTokens / 2);
        swapAVAXSendTo(liquidityPool, liquidityTokens / 2);

        // EXTRA
        uint256 extraT = nodesPrice - developmentFundTokens - rewardsPoolTokens - treasuryPoolTokens - liquidityTokens;
        if (extraT > 0) {
            super._transfer(sender, address(this), extraT);
        }

        _nrm.createNodes(sender, names, _cType);
    }

    function cashoutReward(uint256 _nodeIndex) external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHT: Cashout Disabled");
        require(sender != address(0), "CSHT: zero address");
        require(!_isBlacklisted[sender], "CSHT: this address has been blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = _nrm._getRewardAmountOf(sender, _nodeIndex);
        require(rewardAmount > 0, "CSHT: your reward is not ready yet");

        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            super._transfer(rewardsPool, liquidityPool, feeAmount - feeAmount / 2);
            super._transfer(rewardsPool, address(this), feeAmount / 2);
            swapAVAXSendTo(liquidityPool, feeAmount / 2);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        _nrm._cashoutNodeReward(sender, _nodeIndex);
    }

    function cashoutAll() external {
        address sender = _msgSender();
        require(enableCashout == true, "CSHTALL: cashout disabled");
        require(sender != address(0), "CSHTALL: zero address");
        require(!_isBlacklisted[sender], "CSHTALL: blacklisted address");
        require(sender != developmentFundPool && sender != rewardsPool, "CSHTALL: pools cannot cashout");
        uint256 rewardAmount = _nrm._getRewardAmountOf(sender);
        require(rewardAmount > 0, "CSHTALL: reward not ready");

        // LIQUIDITY POOL
        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            super._transfer(rewardsPool, liquidityPool, feeAmount - feeAmount / 2);
            super._transfer(rewardsPool, address(this), feeAmount / 2);
            swapAVAXSendTo(liquidityPool, feeAmount / 2);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        _nrm._cashoutAllNodesReward(sender);
    }

    // ***** READ function for public *****
    function getRewardAmountOf(address account) external view onlyOwner returns (uint256) {
        return _nrm._getRewardAmountOf(account);
    }

    function getRewardAmount() external view returns (uint256) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getRewardAmountOf(_msgSender());
    }

    function getNodePrice(ContractType _cType) external view returns (uint256) {
        return _nrm.nodePrice(_cType);
    }

    function getRewardAPRPerNode(ContractType _cType) external view returns (uint256) {
        return _nrm.rewardAPRPerNode(_cType);
    }

    function getCashoutTimeout() external view returns (uint256) {
        return _nrm.cashoutTimeout();
    }

    function getNodesNames() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesNames(_msgSender());
    }

    function getNodesCurrentAPR() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesCurrentAPR(_msgSender());
    }

    function getNodesInitialAPR() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesInitialAPR(_msgSender());
    }

    function getNodesCreationTime() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesCreationTime(_msgSender());
    }

    function getNodesTypes() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesTypes(_msgSender());
    }

    function getNodesRewards() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesRewardAvailable(_msgSender());
    }

    function getNodesLastCashoutTime() external view returns (string memory) {
        require(_msgSender() != address(0), "SENDER IS 0");
        require(_nrm._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return _nrm._getNodesLastUpdateTime(_msgSender());
    }

    function getTotalNodes() external view returns (uint256) {
        return _nrm.totalNodesCreated();
    }

    function getTotalNodesPerContractType(ContractType __cType) external view returns (uint256) {
        return _nrm.totalNodesPerContractType(__cType);
    }
}
