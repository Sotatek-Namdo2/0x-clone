// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libraries/IterableMapping.sol";

enum ContractType {
    Square,
    Cube,
    Tesseract
}

contract NODERewardManagement is Initializable {
    using IterableMapping for IterableMapping.Map;

    // ----- Constants -----
    uint256 private constant UNIX_YEAR = 31_536_000;
    uint256 private constant HUNDRED_PERCENT = 100_000_000;

    // ----- Node Structs -----
    struct NodeEntity {
        string name;
        uint256 creationTime;
        uint256 lastUpdateTime;
        uint256 initialAPR;
        uint256 buyPrice;
        ContractType cType;
    }

    // ----- Changes Structs -----
    struct APRChangesEntry {
        uint256 timestamp;
        int256 reducedPercentage;
    }

    // ----- Contract Storage -----
    IterableMapping.Map private nodeOwners;
    mapping(address => NodeEntity[]) private _nodesOfUser;

    mapping(ContractType => uint256) public nodePrice;
    mapping(ContractType => uint256) public rewardAPRPerNode;
    mapping(ContractType => APRChangesEntry[]) private aprChangesHistory;
    uint256 public cashoutTimeout;
    uint256 public autoReduceAPRInterval;
    uint256 public autoReduceAPRRate;

    address public admin0XB;
    address public token;

    uint256 public totalNodesCreated;
    mapping(ContractType => uint256) private _totalNodesPerContractType;

    // ----- Constructor -----
    function initialize(
        uint256[] memory _nodePrices,
        uint256[] memory _rewardAPRs,
        uint256 _cashoutTimeout,
        uint256 _autoReduceAPRRate
    ) public initializer {
        autoReduceAPRInterval = UNIX_YEAR;
        totalNodesCreated = 0;
        uint256 initialTstamp = block.timestamp;
        for (uint256 i = 0; i < 3; i++) {
            nodePrice[ContractType(i)] = _nodePrices[i];
            rewardAPRPerNode[ContractType(i)] = _rewardAPRs[i];
            _totalNodesPerContractType[ContractType(i)] = 0;
            aprChangesHistory[ContractType(i)];
            aprChangesHistory[ContractType(i)].push(
                APRChangesEntry({ timestamp: initialTstamp, reducedPercentage: 0 })
            );
        }
        cashoutTimeout = _cashoutTimeout;
        admin0XB = msg.sender;
        autoReduceAPRRate = _autoReduceAPRRate;
    }

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token || msg.sender == admin0XB, "Access Denied!");
        _;
    }

    // ----- External WRITE functions -----
    function setAdmin(address newAdmin) external onlyAuthorities {
        admin0XB = newAdmin;
    }

    function setToken(address token_) external onlyAuthorities {
        token = token_;
    }

    function createNodes(
        address account,
        string[] memory nodeNames,
        ContractType _cType
    ) external onlyAuthorities {
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

    function _cashoutNodeReward(address account, uint256 _nodeIndex) external onlyAuthorities returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        require(_nodeIndex >= 0 && _nodeIndex < nodes.length, "NODE: Index Error");
        NodeEntity storage node = nodes[_nodeIndex];
        require(claimable(node.lastUpdateTime), "CASHOUT ERROR: You have to wait before claiming this node.");
        uint256 currentTstamp = block.timestamp;
        uint256 rewardNode = nodeCurrentReward(node, currentTstamp);
        node.lastUpdateTime = currentTstamp;
        return rewardNode;
    }

    function _cashoutAllNodesReward(address account) external onlyAuthorities returns (uint256) {
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        require(nodesCount > 0, "CASHOUT ERROR: You don't have nodes to cash-out");
        NodeEntity storage _node;
        uint256 rewardsTotal = 0;
        uint256 currentTstamp = block.timestamp;
        uint256 latestCashout = 0;
        for (uint256 i = 0; i < nodesCount; i++) {
            uint256 lastUpd = nodes[i].lastUpdateTime;
            if (lastUpd > latestCashout) {
                latestCashout = lastUpd;
            }
        }

        require(claimable(latestCashout), "CASHOUT ERROR: You have to wait before claiming all nodes.");

        for (uint256 i = 0; i < nodesCount; i++) {
            _node = nodes[i];
            rewardsTotal += nodeCurrentReward(_node, currentTstamp);
            _node.lastUpdateTime = currentTstamp;
        }
        return rewardsTotal;
    }

    function _changeNodePrice(ContractType _cType, uint256 newPrice) external onlyAuthorities {
        nodePrice[_cType] = newPrice;
    }

    function _changeRewardAPRPerNode(ContractType _cType, int256 reducedPercentage) external onlyAuthorities {
        rewardAPRPerNode[_cType] = reduceByPercent(rewardAPRPerNode[_cType], reducedPercentage);
        aprChangesHistory[_cType].push(
            APRChangesEntry({ timestamp: block.timestamp, reducedPercentage: reducedPercentage })
        );
    }

    function _changeCashoutTimeout(uint256 newTime) external onlyAuthorities {
        cashoutTimeout = newTime;
    }

    function _changeAutoReduceAPRInterval(uint256 newInterval) external onlyAuthorities {
        autoReduceAPRInterval = newInterval;
    }

    function _changeAutoReduceAPRRate(uint256 newRate) external onlyAuthorities {
        autoReduceAPRRate = newRate;
    }

    // ----- External READ functions -----
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
        uint256 currentTstamp = block.timestamp;

        for (uint256 i = 0; i < nodesCount; i++) {
            NodeEntity memory _node = nodes[i];
            rewardCount += nodeCurrentReward(_node, currentTstamp);
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 _nodeIndex) external view returns (uint256) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(_nodeIndex >= 0 && _nodeIndex < numberOfNodes, "NODE: Node index is improper");
        NodeEntity memory node = nodes[_nodeIndex];
        uint256 rewardNode = nodeCurrentReward(node, block.timestamp);
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

    function _getNodesCurrentAPR(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET CREATIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _types = uint2str(currentAPRSingleNode(nodes[0]));
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(currentAPRSingleNode(_node))));
        }
        return _types;
    }

    function _getNodesRewardAvailable(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET REWARD: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        uint256 currentTstamp = block.timestamp;
        string memory _rewardsAvailable = uint2str(nodeCurrentReward(nodes[0], currentTstamp));
        string memory separator = "#";
        for (uint256 i = 1; i < nodesCount; i++) {
            _rewardsAvailable = string(
                abi.encodePacked(_rewardsAvailable, separator, uint2str(nodeCurrentReward(nodes[i], currentTstamp)))
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

    // ----- Private/Internal Helpers -----
    function historyBinarySearch(ContractType _cType, uint256 timestamp) private view returns (uint256) {
        uint256 leftIndex = 0;
        uint256 rightIndex = aprChangesHistory[_cType].length;
        while (rightIndex > leftIndex) {
            uint256 mid = (leftIndex + rightIndex) / 2;
            if (aprChangesHistory[_cType][mid].timestamp < timestamp) leftIndex = mid + 1;
            else rightIndex = mid;
        }
        return leftIndex;
    }

    function currentAPRSingleNode(NodeEntity memory node) private view returns (uint256) {
        return nodeAPRAt(node, block.timestamp);
    }

    function nodeAPRAt(NodeEntity memory node, uint256 tstamp) private view returns (uint256) {
        uint256 creatime = node.creationTime;
        ContractType cType = node.cType;
        uint256 resultAPR = node.initialAPR;
        uint256 startIndex = historyBinarySearch(cType, creatime);
        uint256 endIndex = historyBinarySearch(cType, tstamp);
        for (uint256 i = startIndex; i < endIndex; i++) {
            resultAPR = reduceByPercent(resultAPR, aprChangesHistory[cType][i].reducedPercentage);
        }
        uint256 intervalCount = fullIntervalCount(tstamp, creatime);
        while (intervalCount > 0) {
            intervalCount--;
            resultAPR = reduceByPercent(resultAPR, int256(autoReduceAPRRate));
        }
        return resultAPR;
    }

    function nodeCurrentReward(NodeEntity memory node, uint256 curTstamp) private view returns (uint256) {
        ContractType _cType = node.cType;

        uint256 lastUpdateIndex = historyBinarySearch(_cType, node.lastUpdateTime);

        uint256 nodeBuyPrice = node.buyPrice;
        uint256 itrAPR = nodeAPRAt(node, node.lastUpdateTime);
        uint256 itrTstamp = node.lastUpdateTime;
        uint256 nextTstamp = 0;
        uint256 result = 0;
        uint256 deltaTstamp;
        uint256 intervalReward;
        uint256 creatime = node.creationTime;
        bool diffInterval;
        for (uint256 index = lastUpdateIndex; index < aprChangesHistory[_cType].length; index++) {
            nextTstamp = aprChangesHistory[_cType][index].timestamp;
            diffInterval = (fullIntervalCount(nextTstamp, creatime) != fullIntervalCount(itrTstamp, creatime));
            if (diffInterval) {
                nextTstamp = creatime + autoReduceAPRInterval * (fullIntervalCount(itrTstamp, creatime) + 1);
            }
            deltaTstamp = nextTstamp - itrTstamp;
            intervalReward = (((nodeBuyPrice * itrAPR) / HUNDRED_PERCENT) * deltaTstamp) / UNIX_YEAR;
            itrTstamp = nextTstamp;
            result += intervalReward;

            if (diffInterval) {
                itrAPR = reduceByPercent(itrAPR, int256(autoReduceAPRRate));
                index--;
            } else {
                itrAPR = reduceByPercent(itrAPR, aprChangesHistory[_cType][index].reducedPercentage);
            }
        }

        while (itrTstamp != curTstamp) {
            nextTstamp = curTstamp;
            diffInterval = (fullIntervalCount(nextTstamp, creatime) != fullIntervalCount(itrTstamp, creatime));
            if (diffInterval) {
                nextTstamp = creatime + autoReduceAPRInterval * (fullIntervalCount(itrTstamp, creatime) + 1);
            }
            deltaTstamp = nextTstamp - itrTstamp;
            intervalReward = (((nodeBuyPrice * itrAPR) / HUNDRED_PERCENT) * deltaTstamp) / UNIX_YEAR;
            itrTstamp = nextTstamp;
            result += intervalReward;

            if (diffInterval) {
                itrAPR = reduceByPercent(itrAPR, int256(autoReduceAPRRate));
            }
        }
        return result;
    }

    function fullIntervalCount(uint256 input, uint256 creatime) private view returns (uint256) {
        return (input - creatime) / autoReduceAPRInterval;
    }

    function claimable(uint256 lastUpdateTime) private view returns (bool) {
        return lastUpdateTime + cashoutTimeout <= block.timestamp;
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
