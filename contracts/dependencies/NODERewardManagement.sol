// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/IterableMapping.sol";

enum ContractType {
    Square,
    Cube,
    Tesseract
}

contract NODERewardManagement {
    using IterableMapping for IterableMapping.Map;

    // -------------- Constants --------------
    uint256 public constant UNIX_YEAR = 31536000;
    uint256 private constant HUNDRED_PERCENT = 10000000000000;

    // -------------- Node Structs --------------
    struct NodeEntity {
        string name;
        uint256 creationTime;
        uint256 lastUpdateTime;
        uint256 initialAPR;
        uint256 buyPrice;
        ContractType cType;
    }

    // -------------- Changes Structs --------------
    struct APRChangesEntry {
        uint256 timestamp;
        int256 reducedPercentage;
    }

    // -------------- Contract Storage --------------
    IterableMapping.Map private nodeOwners;
    mapping(address => NodeEntity[]) private _nodesOfUser;

    mapping(ContractType => uint256) public nodePrice;
    mapping(ContractType => uint256) public rewardAPRPerNode;
    mapping(ContractType => APRChangesEntry[]) private aprChangesHistory;
    uint256 public claimTime;

    address public admin0XB;
    address public token;

    bool public distribution = false;

    uint256 public totalNodesCreated = 0;
    mapping(ContractType => uint256) private _totalNodesPerContractType;

    // -------------- Constructor --------------
    constructor(
        uint256[] memory _nodePrices,
        uint256[] memory _rewardAPRs,
        uint256 _claimTime
    ) {
        uint256 initialTimestamp = block.timestamp;
        for (uint256 i = 0; i < 3; i++) {
            nodePrice[ContractType(i)] = _nodePrices[i];
            rewardAPRPerNode[ContractType(i)] = _rewardAPRs[i];
            _totalNodesPerContractType[ContractType(i)] = 0;
            aprChangesHistory[ContractType(i)];
            aprChangesHistory[ContractType(i)].push(
                APRChangesEntry({ timestamp: initialTimestamp, reducedPercentage: 0 })
            );
        }
        claimTime = _claimTime;
        admin0XB = msg.sender;
    }

    // -------------- Modifier (filter) --------------
    modifier onlySentry() {
        require(msg.sender == token || msg.sender == admin0XB, "Access Denied!");
        _;
    }

    // -------------- External WRITE functions --------------
    function setToken(address token_) external onlySentry {
        token = token_;
    }

    function createNodes(
        address account,
        string[] memory nodeNames,
        ContractType _cType
    ) external onlySentry {
        _nodesOfUser[account];

        for (uint256 i = 0; i < nodeNames.length; i++) {
            _nodesOfUser[account].push(
                NodeEntity({
                    name: nodeNames[i],
                    creationTime: block.timestamp,
                    lastUpdateTime: block.timestamp,
                    buyPrice: nodePrice[_cType],
                    initialAPR: rewardAPRPerNode[_cType],
                    cType: _cType
                })
            );
        }

        nodeOwners.set(account, _nodesOfUser[account].length);
        totalNodesCreated += nodeNames.length;
        _totalNodesPerContractType[_cType] += nodeNames.length;
    }

    function _cashoutNodeReward(address account, uint256 _nodeIndex) external onlySentry returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        require(_nodeIndex >= 0 && _nodeIndex < nodes.length, "NODE: Index Error");
        NodeEntity storage node = nodes[_nodeIndex];
        require(claimable(node.lastUpdateTime), "CASHOUT ERROR: You have to wait 3 minutes before claiming this node.");
        uint256 currentTimestamp = block.timestamp;
        uint256 rewardNode = nodeTotalReward(node, currentTimestamp);
        node.lastUpdateTime = currentTimestamp;
        return rewardNode;
    }

    function _cashoutAllNodesReward(address account) external onlySentry returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, "CASHOUT ERROR: You don't have nodes to cash-out");
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        uint256 currentTimestamp = block.timestamp;
        uint256 latestClaim = 0;
        for (uint256 i = 0; i < nodesCount; i++) {
            uint256 lastUpd = nodes[i].lastUpdateTime;
            if (lastUpd > latestClaim) {
                latestClaim = lastUpd;
            }
        }

        require(claimable(latestClaim), "CASHOUT ERROR: You have to wait 3 minutes before claiming all nodes.");

        for (uint256 i = 0; i < nodesCount; i++) {
            _node = nodes[i];
            rewardsTotal += nodeTotalReward(_node, currentTimestamp);
            _node.lastUpdateTime = currentTimestamp;
        }
        return rewardsTotal;
    }

    function _changeNodePrice(ContractType _cType, uint256 newNodePrice) external onlySentry {
        nodePrice[_cType] = newNodePrice;
    }

    function _changeRewardAPRPerNode(ContractType _cType, int256 reducedPercentage) external onlySentry {
        rewardAPRPerNode[_cType] = reduceByPercent(rewardAPRPerNode[_cType], reducedPercentage);
        aprChangesHistory[_cType].push(
            APRChangesEntry({ timestamp: block.timestamp, reducedPercentage: reducedPercentage })
        );
    }

    function _changeClaimTime(uint256 newTime) external onlySentry {
        claimTime = newTime;
    }

    // -------------- External READ functions --------------
    function totalNodesPerContractType(ContractType _cType) external view returns (uint256) {
        return _totalNodesPerContractType[_cType];
    }

    function _isNodeOwner(address account) external view returns (bool) {
        return isNodeOwner(account);
    }

    function _getRewardAmountOf(address account) external view returns (uint256) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        uint256 rewardCount = 0;

        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        uint256 currentTimestamp = block.timestamp;

        for (uint256 i = 0; i < nodesCount; i++) {
            NodeEntity memory _node = nodes[i];
            rewardCount += nodeTotalReward(_node, currentTimestamp);
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 _nodeIndex) external view returns (uint256) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(_nodeIndex >= 0 && _nodeIndex < numberOfNodes, "NODE: Node index is improper");
        NodeEntity memory node = nodes[_nodeIndex];
        uint256 rewardNode = nodeTotalReward(node, block.timestamp);
        return rewardNode;
    }

    function _getNodesNames(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET NAMES: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory names = nodes[0].name;
        string memory separator = "#";
        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            names = string(abi.encodePacked(names, separator, _node.name));
        }
        return names;
    }

    function _getNodesCreationTime(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _creationTimes = uint2str(nodes[0].creationTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            _creationTimes = string(abi.encodePacked(_creationTimes, separator, uint2str(_node.creationTime)));
        }
        return _creationTimes;
    }

    function _getNodesTypes(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _types = uint2str(uint256(nodes[0].cType));
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(uint256(_node.cType))));
        }
        return _types;
    }

    function _getNodesInitialAPR(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _types = uint2str(nodes[0].initialAPR);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(_node.initialAPR)));
        }
        return _types;
    }

    function _getNodesRewardAvailable(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET REWARD: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        uint256 currentTimestamp = block.timestamp;
        string memory _rewardsAvailable = uint2str(nodeTotalReward(nodes[0], currentTimestamp));
        string memory separator = "#";
        for (uint256 i = 1; i < nodesCount; i++) {
            _rewardsAvailable = string(
                abi.encodePacked(_rewardsAvailable, separator, uint2str(nodeTotalReward(nodes[i], currentTimestamp)))
            );
        }
        return _rewardsAvailable;
    }

    function _getNodesLastUpdateTime(address account) external view returns (string memory) {
        require(isNodeOwner(account), "LAST CLAIM TIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _lastUpdateTimes = uint2str(nodes[0].lastUpdateTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _lastUpdateTimes = string(abi.encodePacked(_lastUpdateTimes, separator, uint2str(_node.lastUpdateTime)));
        }
        return _lastUpdateTimes;
    }

    function _getNodeNumberOf(address account) public view returns (uint256) {
        return nodeOwners.get(account);
    }

    // -------------- Private/Internal Helpers --------------
    function nodeTotalReward(NodeEntity memory node, uint256 curTimestamp) private view returns (uint256) {
        uint256 nodeLastUpdate = node.lastUpdateTime;
        ContractType _cType = node.cType;
        uint256 leftIndex = 0;
        uint256 rightIndex = aprChangesHistory[_cType].length;
        while (rightIndex > leftIndex) {
            uint256 mid = (leftIndex + rightIndex) / 2;
            if (aprChangesHistory[_cType][mid].timestamp < nodeLastUpdate) leftIndex = mid + 1;
            else rightIndex = mid;
        }

        uint256 nodeBuyPrice = node.buyPrice;
        uint256 iteratingAPR = node.initialAPR;
        uint256 iteratingTimestamp = node.lastUpdateTime;
        uint256 nextTimestamp = 0;
        uint256 result = 0;
        uint256 deltaTimestamp;
        uint256 periodReward;
        for (uint256 index = leftIndex; index < aprChangesHistory[_cType].length; index++) {
            nextTimestamp = aprChangesHistory[_cType][index].timestamp;
            deltaTimestamp = nextTimestamp - iteratingTimestamp;
            periodReward = (((nodeBuyPrice * iteratingAPR) / HUNDRED_PERCENT) * deltaTimestamp) / UNIX_YEAR;

            result += periodReward;

            iteratingAPR = reduceByPercent(iteratingAPR, aprChangesHistory[_cType][index].reducedPercentage);
            iteratingTimestamp = nextTimestamp;
        }
        nextTimestamp = curTimestamp;
        deltaTimestamp = nextTimestamp - iteratingTimestamp;
        periodReward = (((nodeBuyPrice * iteratingAPR) / HUNDRED_PERCENT) * deltaTimestamp) / UNIX_YEAR;
        result += periodReward;
        return result;
    }

    function claimable(uint256 lastUpdateTime) private view returns (bool) {
        return lastUpdateTime + claimTime <= block.timestamp;
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

    function reduceByPercent(uint256 input, int256 reducePercent) internal pure returns (uint256) {
        uint256 newPercentage = uint256(int256(HUNDRED_PERCENT) - reducePercent);
        return ((input * newPercentage) / HUNDRED_PERCENT);
    }

    function isNodeOwner(address account) private view returns (bool) {
        return nodeOwners.get(account) > 0;
    }
}
