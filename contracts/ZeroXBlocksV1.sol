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

    address public uniswapV2Pair;

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
    uint256 private rwSwap;
    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount;

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
        address uniV2Router
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
        rwSwap = fees[5];

        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;

        require(addresses.length == balances.length, "ADDRESSES AND BALANCES ARRAYS HAVE DIFFERENT SIZES");

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 20456743e18, "`totalSupply` NEEDS TO EQUAL 20 MILLIONS");
        require(swapAmount > 0, "`swapAmount` NEEDS TO BE POSITIVE");
        swapTokensAmount = swapAmount * (10**18);
    }

    // *************** WRITE functions for admin ***************
    function setEnableCashout(bool _enableCashout) external onlyOwner {
        enableCashout = _enableCashout;
    }

    function setNodeManagement(address nodeManagement) external onlyOwner {
        nodeRewardManager = NODERewardManagement(nodeManagement);
    }

    function changeNodePrice(ContractType cType, uint256 newNodePrice) public onlyOwner {
        nodeRewardManager._changeNodePrice(cType, newNodePrice);
    }

    function changeRewardAPYPerNode(ContractType cType, uint256 newPrice) public onlyOwner {
        nodeRewardManager._changeRewardAPYPerNode(cType, newPrice);
    }

    function changeClaimTime(uint256 newTime) public onlyOwner {
        nodeRewardManager._changeClaimTime(newTime);
    }

    function confirmRewardUpdates() public onlyOwner returns (string memory) {
        return nodeRewardManager._confirmRewardUpdates();
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

    function updateDevelopmentFundWall(address payable wall) external onlyOwner {
        developmentFundPool = wall;
    }

    function updateLiquidityWall(address payable wall) external onlyOwner {
        liquidityPool = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        rewardsPool = wall;
    }

    function updateTreasuryWall(address payable wall) external onlyOwner {
        treasuryPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;
    }

    function updateLiquidityFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;
    }

    function updateDevelopmentFee(uint256 value) external onlyOwner {
        developmentFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;
    }

    function updateTreasuryFee(uint256 value) external onlyOwner {
        treasuryFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (developmentFee) + treasuryFee;
    }

    function updateCashoutFee(uint256 value) external onlyOwner {
        cashoutFee = value;
    }

    function updateRwSwapFee(uint256 value) external onlyOwner {
        rwSwap = value;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "TKN: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function blacklistMalicious(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function boostReward(uint256 amount) public onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    function changeSwapLiquify(bool newVal) public onlyOwner {
        swapLiquify = newVal;
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
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "ERC20: Blacklisted address");

        super._transfer(from, to, amount);
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBalance = (address(this).balance) - (initialETHBalance);
        payable(destination).transfer(newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens / (2);
        uint256 otherHalf = tokens - (half);

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half);

        uint256 newBalance = address(this).balance - (initialBalance);

        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WAVAX();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityAVAX{ value: ethAmount }(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    // *************** WRITE functions for public ***************
    function createMultipleNodesWithTokens(string[] memory names, ContractType cType) public {
        for (uint256 i = 0; i < names.length; i++) {
            require(
                bytes(names[i]).length > 3 && bytes(names[i]).length < 33,
                "NODE CREATION: node name must be between 4 and 32 characters"
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
        uint256 nodePrice = nodeRewardManager.nodePrice(cType) * names.length;
        require(balanceOf(sender) >= nodePrice, "NODE CREATION: Balance too low for creation.");

        // distribute to wallets
        swapping = true;

        uint256 developmentFundTokens = (nodePrice * (developmentFee)) / (100);
        super._transfer(sender, developmentFundPool, developmentFundTokens);

        uint256 rewardsPoolTokens = (nodePrice * (rewardsFee)) / (100);
        super._transfer(sender, rewardsPool, rewardsPoolTokens);

        uint256 treasuryPoolTokens = (nodePrice * (treasuryFee)) / (100);
        super._transfer(sender, treasuryPool, treasuryPoolTokens);

        uint256 liquidityTokens = (nodePrice * (liquidityPoolFee)) / (100);
        super._transfer(sender, liquidityPool, liquidityTokens);

        uint256 extraT = nodePrice - developmentFundTokens - rewardsPoolTokens - treasuryPoolTokens - liquidityTokens;
        if (extraT > 0) {
            super._transfer(sender, address(this), extraT);
        }

        swapping = false;

        // create node
        for (uint256 i = 0; i < names.length; i++) {
            nodeRewardManager.createNode(sender, names[i], cType);
        }
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

        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = (rewardAmount * (cashoutFee)) / (100);
                // swapAndSendToFee(developmentFundPool, feeAmount);
                super._transfer(rewardsPool, developmentFundPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
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
        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = (rewardAmount * (cashoutFee)) / (100);
                // swapAndSendToFee(developmentFundPool, feeAmount);
                super._transfer(rewardsPool, developmentFundPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
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

    function getNodePrice(ContractType cType) public view returns (uint256) {
        return nodeRewardManager.nodePrice(cType);
    }

    function getRewardAPYPerNode(ContractType cType) public view returns (uint256) {
        return nodeRewardManager.rewardAPYPerNode(cType);
    }

    function getClaimTime() public view returns (uint256) {
        return nodeRewardManager.claimTime();
    }

    function getNodesNames() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesNames(_msgSender());
    }

    function getNodesInitialAPY() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesInitialAPY(_msgSender());
    }

    function getNodesCreatime() public view returns (string memory) {
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

    function getTotalCreatedNodes() public view returns (uint256) {
        return nodeRewardManager.totalNodesCreated();
    }

    function getTotalCreatedNodesPerContractType(ContractType _contractType) public view returns (uint256) {
        return nodeRewardManager.totalNodesPerContractType(_contractType);
    }
}
