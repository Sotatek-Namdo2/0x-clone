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

    address public uniswapV2Pair;
    address public futureUsePool;
    address public distributionPool;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public futureFee;
    uint256 public totalFees;

    uint256 public cashoutFee;

    uint256 private rwSwap;
    bool private swapping = false;
    bool private swapLiquify = true;
    uint256 public swapTokensAmount;

    mapping(address => bool) public _isBlacklisted;
    mapping(address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);

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

        futureUsePool = addresses[4];
        distributionPool = addresses[5];

        require(futureUsePool != address(0), "PLEASE PROVIDE PROPER FUTURE POOL ADDRESS.");
        require(distributionPool != address(0), "PLEASE PROVIDE PROPER DISTRIBUTION POOL ADDRESS.");

        require(uniV2Router != address(0), "PLEASE PROVIDE PROPER ROUTER ADDRESS.");
        IJoeRouter02 _uniswapV2Router = IJoeRouter02(uniV2Router);

        address _uniswapV2Pair = IJoeFactory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WAVAX()
        );

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        require(fees[0] > 0 && fees[1] > 0 && fees[2] > 0 && fees[3] > 0, "ALL FEES MUST BE GREATER THAN 0.");
        futureFee = fees[0];
        rewardsFee = fees[1];
        liquidityPoolFee = fees[2];
        cashoutFee = fees[3];
        rwSwap = fees[4];

        totalFees = rewardsFee + (liquidityPoolFee) + (futureFee);

        require(addresses.length == balances.length, "ADDRESSES AND BALANCES ARRAYS HAVE DIFFERENT SIZES");

        for (uint256 i = 0; i < addresses.length; i++) {
            _mint(addresses[i], balances[i] * (10**18));
        }
        require(totalSupply() == 20456743e18, "`totalSupply` NEEDS TO EQUAL 20 MILLIONS");
        require(swapAmount > 0, "`swapAmount` NEEDS TO BE POSITIVE");
        swapTokensAmount = swapAmount * (10**18);
    }

    function setNodeManagement(address nodeManagement) external onlyOwner {
        nodeRewardManager = NODERewardManagement(nodeManagement);
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

    function updateFutureWall(address payable wall) external onlyOwner {
        futureUsePool = wall;
    }

    function updateRewardsWall(address payable wall) external onlyOwner {
        distributionPool = wall;
    }

    function updateRewardsFee(uint256 value) external onlyOwner {
        rewardsFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (futureFee);
    }

    function updateLiquiditFee(uint256 value) external onlyOwner {
        liquidityPoolFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (futureFee);
    }

    function updatefutureFee(uint256 value) external onlyOwner {
        futureFee = value;
        totalFees = rewardsFee + (liquidityPoolFee) + (futureFee);
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

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "THIS ADDRESS HAS BEEN BLACKLISTED!");

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

    function createNodeWithTokens(string memory name, ContractType cType) public {
        require(
            bytes(name).length > 3 && bytes(name).length < 33,
            "NODE CREATION: node name must be between 4 and 32 characters"
        );
        address sender = _msgSender();
        require(sender != address(0), "NODE CREATION: creation from the zero address");
        require(!_isBlacklisted[sender], "NODE CREATION: this address has been blacklisted");
        require(
            sender != futureUsePool && sender != distributionPool,
            "NODE CREATION: future and reward pools cannot create node"
        );
        uint256 nodePrice = nodeRewardManager.nodePrice(cType);
        require(balanceOf(sender) >= nodePrice, "NODE CREATION: Balance too low for creation.");
        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && swapLiquify && !swapping && sender != owner() && !automatedMarketMakerPairs[sender]) {
            swapping = true;

            uint256 futureTokens = (contractTokenBalance * (futureFee)) / (100);

            swapAndSendToFee(futureUsePool, futureTokens);

            uint256 rewardsPoolTokens = (contractTokenBalance * (rewardsFee)) / (100);

            uint256 rewardsTokenstoSwap = (rewardsPoolTokens * (rwSwap)) / (100);

            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(address(this), distributionPool, rewardsPoolTokens - (rewardsTokenstoSwap));

            uint256 swapTokens = (contractTokenBalance * (liquidityPoolFee)) / (100);

            swapAndLiquify(swapTokens);

            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice);
        nodeRewardManager.createNode(sender, name, cType);
    }

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
            sender != futureUsePool && sender != distributionPool,
            "NODE CREATION: future and reward pools cannot create node"
        );
        uint256 nodePrice = nodeRewardManager.nodePrice(cType);
        require(balanceOf(sender) >= nodePrice, "NODE CREATION: Balance too low for creation.");
        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && swapLiquify && !swapping && sender != owner() && !automatedMarketMakerPairs[sender]) {
            swapping = true;

            uint256 futureTokens = (contractTokenBalance * (futureFee)) / (100);

            swapAndSendToFee(futureUsePool, futureTokens);

            uint256 rewardsPoolTokens = (contractTokenBalance * (rewardsFee)) / (100);

            uint256 rewardsTokenstoSwap = (rewardsPoolTokens * (rwSwap)) / (100);

            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(address(this), distributionPool, rewardsPoolTokens - (rewardsTokenstoSwap));

            uint256 swapTokens = (contractTokenBalance * (liquidityPoolFee)) / (100);

            swapAndLiquify(swapTokens);

            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), nodePrice);
        for (uint256 i = 0; i < names.length; i++) {
            nodeRewardManager.createNode(sender, names[i], cType);
        }
    }

    function cashoutReward(uint256 _nodeIndex) public {
        address sender = _msgSender();
        require(sender != address(0), "CSHT: zero address");
        require(!_isBlacklisted[sender], "CSHT: this address has been blacklisted");
        require(
            sender != futureUsePool && sender != distributionPool,
            "CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender, _nodeIndex);
        require(rewardAmount > 0, "CSHT: your reward is not ready yet");

        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = (rewardAmount * (cashoutFee)) / (100);
                swapAndSendToFee(futureUsePool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutNodeReward(sender, _nodeIndex);
    }

    function cashoutAll() public {
        address sender = _msgSender();
        require(sender != address(0), "MANIA CSHT: zero address");
        require(!_isBlacklisted[sender], "MANIA CSHT: this address has been blacklisted");
        require(
            sender != futureUsePool && sender != distributionPool,
            "MANIA CSHT: future and reward pools cannot cashout rewards"
        );
        uint256 rewardAmount = nodeRewardManager._getRewardAmountOf(sender);
        require(rewardAmount > 0, "MANIA CSHT: your reward is not ready yet");
        if (swapLiquify) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = (rewardAmount * (cashoutFee)) / (100);
                swapAndSendToFee(futureUsePool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(distributionPool, sender, rewardAmount);
        nodeRewardManager._cashoutAllNodesReward(sender);
    }

    function boostReward(uint256 amount) public onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    function changeSwapLiquify(bool newVal) public onlyOwner {
        swapLiquify = newVal;
    }

    function getNodeNumberOf(address account) public view returns (uint256) {
        return nodeRewardManager._getNodeNumberOf(account);
    }

    function getRewardAmountOf(address account) public view onlyOwner returns (uint256) {
        return nodeRewardManager._getRewardAmountOf(account);
    }

    function getRewardAmount() public view returns (uint256) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getRewardAmountOf(_msgSender());
    }

    function changeNodePrice(ContractType cType, uint256 newNodePrice) public onlyOwner {
        nodeRewardManager._changeNodePrice(cType, newNodePrice);
    }

    function getNodePrice(ContractType cType) public view returns (uint256) {
        return nodeRewardManager.nodePrice(cType);
    }

    function changeRewardAPYPerNode(ContractType cType, uint256 newPrice) public onlyOwner {
        nodeRewardManager._changeRewardAPYPerNode(cType, newPrice);
    }

    function getRewardAPYPerNode(ContractType cType) public view returns (uint256) {
        return nodeRewardManager.rewardAPYPerNode(cType);
    }

    function changeClaimTime(uint256 newTime) public onlyOwner {
        nodeRewardManager._changeClaimTime(newTime);
    }

    function getClaimTime() public view returns (uint256) {
        return nodeRewardManager.claimTime();
    }

    function changeAutoDistribution(bool newMode) public onlyOwner {
        nodeRewardManager._changeAutoDistribute(newMode);
    }

    function getAutoDistribution() public view returns (bool) {
        return nodeRewardManager.autoDistribute();
    }

    function getNodesNames() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesNames(_msgSender());
    }

    function getNodesCreatime() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesCreationTime(_msgSender());
    }

    function getNodesRewards() public view returns (string memory) {
        require(_msgSender() != address(0), "SENDER CAN'T BE ZERO");
        require(nodeRewardManager._isNodeOwner(_msgSender()), "NO NODE OWNER");
        return nodeRewardManager._getNodesRewardAvailable(_msgSender());
    }

    function getTotalCreatedNodes() public view returns (uint256) {
        return nodeRewardManager.totalNodesCreated();
    }
}
