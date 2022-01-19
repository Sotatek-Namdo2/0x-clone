// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libraries/IterableMapping.sol";

enum ContractType {
    Fine,
    Mean,
    Finest
}

contract NODERewardManagement {
    using IterableMapping for IterableMapping.Map;

    // -------------- Node Structs --------------
    struct NodeEntity {
        string name;
        uint256 creationTime;
        uint256 lastClaimTime;
        uint256 rewardAvailable;
        ContractType cType;
    }

    // -------------- Contract Storage --------------
    IterableMapping.Map private nodeOwners;
    mapping(address => NodeEntity[]) private _nodesOfUser;

    mapping(ContractType => uint256) public nodePrice;
    mapping(ContractType => uint256) public rewardPerNode;
    uint256 public claimTime;

    address public admin0XB;
    address public token;

    bool public autoDistribute = true;
    bool public distribution = false;

    uint256 public totalNodesCreated = 0;

    // -------------- Constructor --------------
    constructor(
        uint256 _nodePriceFine,
        uint256 _nodePriceMean,
        uint256 _nodePriceFinest,
        uint256 _rewardPerNodeFine,
        uint256 _rewardPerNodeMean,
        uint256 _rewardPerNodeFinest,
        uint256 _claimTime
    ) {
        nodePrice[ContractType.Fine] = _nodePriceFine;
        nodePrice[ContractType.Mean] = _nodePriceMean;
        nodePrice[ContractType.Finest] = _nodePriceFinest;
        rewardPerNode[ContractType.Fine] = _rewardPerNodeFine;
        rewardPerNode[ContractType.Mean] = _rewardPerNodeMean;
        rewardPerNode[ContractType.Finest] = _rewardPerNodeFinest;
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

    function createNode(
        address account,
        string memory nodeName,
        ContractType _cType
    ) external onlySentry {
        require(isNameAvailable(account, nodeName), "CREATE NODE: Name not available.");

        _nodesOfUser[account];

        if (isNodeOwner(account)) {
            require(
                _cType == _nodesOfUser[account][0].cType,
                "CREATE NODE: Contract type of new node must be the same of current nodes."
            );
        }

        _nodesOfUser[account].push(
            NodeEntity({
                name: nodeName,
                creationTime: block.timestamp,
                lastClaimTime: block.timestamp,
                rewardAvailable: rewardPerNode[_cType],
                cType: _cType
            })
        );
        nodeOwners.set(account, _nodesOfUser[account].length);
        totalNodesCreated++;
    }

    // function _cashoutNodeReward(address account, uint256 _creationTime) external onlySentry returns (uint256) {
    //     require(_creationTime > 0, "NODE: CREATIME must be higher than zero");
    //     NodeEntity[] storage nodes = _nodesOfUser[account];
    //     uint256 numberOfNodes = nodes.length;
    //     require(numberOfNodes > 0, "CASHOUT ERROR: You don't have nodes to cash-out");
    //     NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
    //     uint256 rewardNode = node.rewardAvailable;
    //     node.rewardAvailable = 0;
    //     return rewardNode;
    // }

    // function _cashoutAllNodesReward(address account) external onlySentry returns (uint256) {
    //     NodeEntity[] storage nodes = _nodesOfUser[account];
    //     uint256 nodesCount = nodes.length;
    //     require(nodesCount > 0, "CASHOUT ERROR: You don't have nodes to cash-out");
    //     NodeEntity storage _node;
    //     uint256 rewardsTotal = 0;
    //     for (uint256 i = 0; i < nodesCount; i++) {
    //         _node = nodes[i];
    //         rewardsTotal += _node.rewardAvailable;
    //         _node.rewardAvailable = 0;
    //     }
    //     return rewardsTotal;
    // }

    function _changeNodePrice(ContractType _cType, uint256 newNodePrice) external onlySentry {
        nodePrice[_cType] = newNodePrice;
    }

    function _changeRewardPerNode(ContractType _cType, uint256 newPrice) external onlySentry {
        rewardPerNode[_cType] = newPrice;
    }

    function _changeClaimTime(uint256 newTime) external onlySentry {
        claimTime = newTime;
    }

    function _changeAutoDistribute(bool newMode) external onlySentry {
        autoDistribute = newMode;
    }

    // function _changeGasDistri(uint256 newGasDistri) external onlySentry {
    //     gasForDistribution = newGasDistri;
    // }

    // -------------- External READ functions --------------
    function _isNodeOwner(address account) external view returns (bool) {
        return isNodeOwner(account);
    }

    function _getTierOfAccount(address account) external view returns (ContractType) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        NodeEntity[] storage nodes = _nodesOfUser[account];
        ContractType res = nodes[0].cType;

        return res;
    }

    function _getRewardAmountOf(address account) external view returns (uint256) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");
        uint256 nodesCount;
        uint256 rewardCount = 0;

        NodeEntity[] storage nodes = _nodesOfUser[account];
        nodesCount = nodes.length;

        for (uint256 i = 0; i < nodesCount; i++) {
            rewardCount += nodes[i].rewardAvailable;
        }

        return rewardCount;
    }

    function _getRewardAmountOf(address account, uint256 _creationTime) external view returns (uint256) {
        require(isNodeOwner(account), "GET REWARD OF: NO NODE OWNER");

        require(_creationTime > 0, "NODE: CREATIME must be higher than zero");
        NodeEntity[] storage nodes = _nodesOfUser[account];
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, "CASHOUT ERROR: You don't have nodes to cash-out");
        NodeEntity storage node = _getNodeWithCreatime(nodes, _creationTime);
        uint256 rewardNode = node.rewardAvailable;
        return rewardNode;
    }

    function _getNodeRewardAmountOf(address account, uint256 creationTime) external view returns (uint256) {
        return _getNodeWithCreatime(_nodesOfUser[account], creationTime).rewardAvailable;
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

    function _getNodesRewardAvailable(address account) external view returns (string memory) {
        require(isNodeOwner(account), "GET REWARD: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _rewardsAvailable = uint2str(nodes[0].rewardAvailable);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _rewardsAvailable = string(abi.encodePacked(_rewardsAvailable, separator, uint2str(_node.rewardAvailable)));
        }
        return _rewardsAvailable;
    }

    function _getNodesLastClaimTime(address account) external view returns (string memory) {
        require(isNodeOwner(account), "LAST CLAIM TIME: NO NODE OWNER");
        NodeEntity[] memory nodes = _nodesOfUser[account];
        uint256 nodesCount = nodes.length;
        NodeEntity memory _node;
        string memory _lastClaimTimes = uint2str(nodes[0].lastClaimTime);
        string memory separator = "#";

        for (uint256 i = 1; i < nodesCount; i++) {
            _node = nodes[i];

            _lastClaimTimes = string(abi.encodePacked(_lastClaimTimes, separator, uint2str(_node.lastClaimTime)));
        }
        return _lastClaimTimes;
    }

    // -------------- Private/Internal Helpers --------------
    function isNameAvailable(address account, string memory nodeName) private view returns (bool) {
        NodeEntity[] memory nodes = _nodesOfUser[account];
        for (uint256 i = 0; i < nodes.length; i++) {
            if (keccak256(bytes(nodes[i].name)) == keccak256(bytes(nodeName))) {
                return false;
            }
        }
        return true;
    }

    function _burn(uint256 index) internal {
        require(index < nodeOwners.size(), "Index Out of Bounds.");
        nodeOwners.remove(nodeOwners.getKeyAtIndex(index));
    }

    function _getNodeWithCreatime(NodeEntity[] storage nodes, uint256 _creationTime)
        private
        view
        returns (NodeEntity storage)
    {
        uint256 numberOfNodes = nodes.length;
        require(numberOfNodes > 0, "CASHOUT ERROR: You don't have nodes to cash-out.");
        bool found = false;
        int256 index = binarySearch(nodes, 0, numberOfNodes, _creationTime);
        uint256 validIndex;
        if (index >= 0) {
            found = true;
            validIndex = uint256(index);
        }
        require(found, "NODE SEARCH: No NODE Found with this blocktime.");
        return nodes[validIndex];
    }

    function binarySearch(
        NodeEntity[] memory arr,
        uint256 low,
        uint256 high,
        uint256 x
    ) private pure returns (int256) {
        uint256 _h = high;
        uint256 _l = low;
        while (_h > _l) {
            uint256 mid = (high + low) / 2;
            if (arr[mid].creationTime < x) {
                _l = mid + 1;
            } else {
                _h = mid;
            }
        }
        return ((arr[_l].creationTime == x) ? int256(_l) : int256(-1));
    }

    function claimable(NodeEntity memory node) private view returns (bool) {
        return node.lastClaimTime + claimTime <= block.timestamp;
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

    function _getNodeNumberOf(address account) public view returns (uint256) {
        return nodeOwners.get(account);
    }

    function isNodeOwner(address account) private view returns (bool) {
        return nodeOwners.get(account) > 0;
    }
}
