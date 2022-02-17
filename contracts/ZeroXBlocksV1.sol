// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "./dependencies/NODERewardManagement.sol";
import "./interfaces/IJoeRouter02.sol";
import "./interfaces/IJoeFactory.sol";

contract ZeroXBlocksV1 is ERC20, Ownable, PaymentSplitter {
    NODERewardManagement public nodeRewardManager;

    IJoeRouter02 public uniswapV2Router;

    uint256 public ownedNodesCountLimit = 100;
    uint256 private mintNodeLimit = 10;

    address public uniswapV2Pair;

    uint256 public totalTokensPaidForMinting;

    // *************** Pools Address ***************
    address public developmentFundPool;
    address public treasuryPool;
    address public rewardsPool;
    address public liquidityPool;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    // *************** Storage for fees ***************
    uint256 public rewardsFee;
    uint256 public treasuryFee;
    uint256 public liquidityPoolFee;
    uint256 public developmentFee;
    uint256 public totalFees;
    uint256 public cashoutFee;

    // *************** Storage for swapping ***************
    bool public enableAutoSwap = true;
    uint256 public swapTokensAmount = 0;
    address public usdcToken;

    // *************** Blacklist storage ***************
    mapping(address => bool) public _isBlacklisted;

    // *************** Market makers pairs ***************
    mapping(address => bool) public automatedMarketMakerPairs;

    // *************** Events ***************
    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);

    // *************** Enable Cashout ***************
    bool public enableCashout = true;

    // *************** Constructor ***************
    constructor(
        address[] memory payees,
        uint256[] memory shares,
        address[] memory addresses,
        uint256[] memory balances,
        uint256[] memory fees,
        uint256 swapAmount,
        address uniV2Router,
        address usdcAddr
    ) ERC20("0xBlocks v2", "0XB") PaymentSplitter(payees, shares) {
        require(addresses.length > 0 && balances.length > 0, "THERE MUST BE AT LEAST ONE ADDRESS AND BALANCES.");

        developmentFundPool = addresses[1];
        liquidityPool = addresses[2];
        treasuryPool = addresses[3];
        rewardsPool = addresses[4];

        require(developmentFundPool != address(0), "PLEASE PROVIDE PROPER DEVELOPMENT FUND POOL ADDRESS.");
        require(liquidityPool != address(0), "PLEASE PROVIDE PROPER LIQUIDITY POOL ADDRESS.");
        require(treasuryPool != address(0), "PLEASE PROVIDE PROPER TREASURY POOL ADDRESS.");
        require(rewardsPool != address(0), "PLEASE PROVIDE PROPER REWARDS POOL ADDRESS.");

        require(uniV2Router != address(0), "PLEASE PROVIDE PROPER ROUTER ADDRESS.");
        IJoeRouter02 _uniswapV2Router = IJoeRouter02(uniV2Router);

        address _uniswapV2Pair = IJoeFactory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WAVAX()
        );

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        require(fees[0] > 0 && fees[1] > 0 && fees[2] > 0 && fees[3] > 0, "ALL FEES MUST BE GREATER THAN 0%.");
        developmentFee = fees[0];
        treasuryFee = fees[1];
        rewardsFee = fees[2];
        liquidityPoolFee = fees[3];
        cashoutFee = fees[4];

        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;

        require(addresses.length == balances.length, "ADDRESSES AND BALANCES ARRAYS HAVE DIFFERENT SIZES");

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 20456743e18, "`totalSupply` NEEDS TO EQUAL 20 MILLIONS");
        require(swapAmount > 0, "`swapAmount` NEEDS TO BE POSITIVE");
        swapTokensAmount = swapAmount * (10**18);

        usdcToken = usdcAddr;
    }

    // *************** WRITE functions for admin ***************
    function setEnableCashout(bool _enableCashout) external onlyOwner {
        enableCashout = _enableCashout;
    }

    function setNodeManagement(address nodeManagement) external onlyOwner {
        nodeRewardManager = NODERewardManagement(nodeManagement);
    }

    function changeNodePrice(ContractType contractType, uint256 newNodePrice) public onlyOwner {
        nodeRewardManager._changeNodePrice(contractType, newNodePrice);
    }

    function changeRewardAPRPerNode(ContractType contractType, int256 reducePercentage) public onlyOwner {
        nodeRewardManager._changeRewardAPRPerNode(contractType, reducePercentage);
    }

    function changeCashoutTimeout(uint256 newTime) public onlyOwner {
        nodeRewardManager._changeCashoutTimeout(newTime);
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "TKN: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
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
        uint256 newTotalFee = (liquidityPoolFee) + (developmentFee) + treasuryFee + value;
        require(newTotalFee <= 100, "UPDATE FEES: total fee percentage exceeding 100%");
        rewardsFee = value;
        totalFees = newTotalFee;
    }

    function updateLiquidityFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + (developmentFee) + treasuryFee + value;
        require(newTotalFee <= 100, "UPDATE FEES: total fee percentage exceeding 100%");
        liquidityPoolFee = value;
        totalFees = newTotalFee;
    }

    function updateDevelopmentFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + (liquidityPoolFee) + treasuryFee + value;
        require(newTotalFee <= 100, "UPDATE FEES: total fee percentage exceeding 100%");
        developmentFee = value;
        totalFees = newTotalFee;
    }

    function updateTreasuryFee(uint256 value) external onlyOwner {
        uint256 newTotalFee = rewardsFee + (liquidityPoolFee) + (developmentFee) + value;
        require(newTotalFee <= 100, "UPDATE FEES: total fee percentage exceeding 100%");
        treasuryFee = value;
        totalFees = newTotalFee;
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        require(value <= 100, "UPDATE FEES: cashout percentage exceeding 100%");
        cashoutFee = value;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "TKN: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function setBlacklistStatus(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function changeEnableAutoSwap(bool newVal) public onlyOwner {
        enableAutoSwap = newVal;
    }

    // *************** Private helpers functions ***************
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function getNodeNumberOf(address account) private view returns (uint256) {
        return nodeRewardManager._getNodeNumberOf(account);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");

        super._transfer(from, to, amount);
    }

    function swapToAVAXIfEnabledAndSendToWallet(address targetWallet, uint256 tokens) private {
        if (enableAutoSwap) {
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = uniswapV2Router.WAVAX();

            _approve(address(this), address(uniswapV2Router), tokens);

            uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
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

    function swapToUSDCIfEnabledAndSendToWallet(address targetWallet, uint256 tokens) private {
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

    // *************** WRITE functions for public ***************
    function mintNodes(string[] memory names, ContractType contractType) public {
        require(names.length <= mintNodeLimit, "NODE CREATION: too many nodes created at the same time");
        for (uint256 i = 0; i < names.length; i++) {
            require(
                bytes(names[i]).length > 3 && bytes(names[i]).length < 33,
                "NODE CREATION: node name must have proper amount of characters"
            );
        }

        address sender = _msgSender();
        require(sender != address(0), "NODE CREATION: creation from the zero address");
        require(!_isBlacklisted[sender], "NODE CREATION: this address has been blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "NODE CREATION: fund, reward and treasury pools cannot create node"
        );
        uint256 nodeCount = getNodeNumberOf(sender);
        require(
            nodeCount + names.length <= ownedNodesCountLimit,
            "NODE CREATION: address reached limit of owned nodes"
        );
        uint256 nodesPrice = nodeRewardManager.nodePrice(contractType) * names.length;
        totalTokensPaidForMinting += nodesPrice;
        require(balanceOf(sender) >= nodesPrice, "NODE CREATION: Balance too low for creation.");

        // distribute to wallets
        // DEV FUND
        uint256 developmentFundTokens = (nodesPrice * (developmentFee)) / (100);
        super._transfer(sender, address(this), developmentFundTokens);
        swapToUSDCIfEnabledAndSendToWallet(developmentFundPool, developmentFundTokens);

        // REWARDS POOL
        uint256 rewardsPoolTokens = (nodesPrice * (rewardsFee)) / (100);
        super._transfer(sender, rewardsPool, rewardsPoolTokens);

        // TREASURY
        uint256 treasuryPoolTokens = (nodesPrice * (treasuryFee)) / (100);
        super._transfer(sender, address(this), treasuryPoolTokens);
        swapToUSDCIfEnabledAndSendToWallet(treasuryPool, treasuryPoolTokens);

        // LIQUIDITY
        uint256 liquidityTokens = (nodesPrice * (liquidityPoolFee)) / (100);
        super._transfer(sender, liquidityPool, liquidityTokens - liquidityTokens / 2);
        super._transfer(sender, address(this), liquidityTokens / 2);
        swapToAVAXIfEnabledAndSendToWallet(liquidityPool, liquidityTokens / 2);

        // EXTRA
        uint256 extraT = nodesPrice - developmentFundTokens - rewardsPoolTokens - treasuryPoolTokens - liquidityTokens;
        if (extraT > 0) {
            super._transfer(sender, address(this), extraT);
        }

        nodeRewardManager.createNodes(sender, names, contractType);
    }

    function cashoutReward(uint256 _nodeIndex) public {
        address sender = _msgSender();
        require(enableCashout == true, "CSHT: Cashout Disabled");
        require(sender != address(0), "CSHT: zero address");
        require(!_isBlacklisted[sender], "CSHT: this address has been blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool && sender != treasuryPool,
            "CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender, _nodeIndex);
        require(rewardAmount > 0, "CSHT: your reward is not ready yet");

        // LIQUIDITY POOL
        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            super._transfer(rewardsPool, liquidityPool, feeAmount - feeAmount / 2);
            super._transfer(rewardsPool, address(this), feeAmount / 2);
            swapToAVAXIfEnabledAndSendToWallet(liquidityPool, feeAmount / 2);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        nodeRewardManager._cashoutNodeReward(sender, _nodeIndex);
    }

    function cashoutAll() public {
        address sender = _msgSender();
        require(enableCashout == true, "MANIA CSHT: Cashout Disabled");
        require(sender != address(0), "MANIA CSHT: zero address");
        require(!_isBlacklisted[sender], "MANIA CSHT: this address has been blacklisted");
        require(
            sender != developmentFundPool && sender != rewardsPool,
            "MANIA CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender);
        require(rewardAmount > 0, "MANIA CSHT: your reward is not ready yet");

        // LIQUIDITY POOL
        uint256 feeAmount = 0;
        if (cashoutFee > 0) {
            feeAmount = (rewardAmount * (cashoutFee)) / (100);
            super._transfer(rewardsPool, liquidityPool, feeAmount - feeAmount / 2);
            super._transfer(rewardsPool, address(this), feeAmount / 2);
            swapToAVAXIfEnabledAndSendToWallet(liquidityPool, feeAmount / 2);
        }
        rewardAmount -= feeAmount;

        super._transfer(rewardsPool, sender, rewardAmount);
        nodeRewardManager._cashoutAllNodesReward(sender);
    }

    // *************** READ function for public ***************
    function getRewardAmountOf(address account) public view onlyOwner returns (uint256) {
        return nodeRewardManager._getRewardAmountOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getRewardAmountOf(_msgSender());
    }

    function getNodePrice(ContractType contractType) public view returns (uint256) {
        return nodeRewardManager.nodePrice(contractType);
    }

    function getRewardAPRPerNode(ContractType contractType) public view returns (uint256) {
        return nodeRewardManager.rewardAPRPerNode(contractType);
    }

    function getCashoutTimeout() public view returns (uint256) {
        return nodeRewardManager.cashoutTimeout();
    }

    function getNodesNames() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesNames(_msgSender());
    }

    function getNodesCurrentAPR() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesCurrentAPR(_msgSender());
    }

    function getNodesInitialAPR() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesInitialAPR(_msgSender());
    }

    function getNodesCreationTime() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesCreationTime(_msgSender());
    }

    function getNodesTypes() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesTypes(_msgSender());
    }

    function getNodesRewards() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesRewardAvailable(_msgSender());
    }

    function getNodesLastCashoutTime() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesLastUpdateTime(_msgSender());
    }

    function getTotalCreatedNodes() public view returns (uint256) {
        return nodeRewardManager.totalNodesCreated();
    }

    function getTotalCreatedNodesPerContractType(ContractType _contractType) public view returns (uint256) {
        return nodeRewardManager.totalNodesPerContractType(_contractType);
    }
}
