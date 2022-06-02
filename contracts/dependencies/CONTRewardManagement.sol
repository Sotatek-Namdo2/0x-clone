// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../libraries/IterableMapping.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

enum ContType {
    Square,
    Cube,
    Tesseract,
    Other
}

contract CONTRewardManagement is Initializable {
    using IterableMapping for IterableMapping.Map;

    // ----- Constants -----
    uint256 private constant UNIX_YEAR = 31_536_000;
    uint256 private constant HUNDRED_PERCENT = 100_000_000;
    uint256 private constant ADDITION_TIME_FOR_OLD = 10 days;
    uint256 private constant ADDITION_TIME_FOR_NEW = 30 days;
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant TWO_MONTH = 60 days;
    uint256 public constant THREE_MONTH = 90 days;
    uint256 public constant FOUR_MONTH = 120 days;
    uint256 public constant MAXUINT256 = type(uint256).max;

    // ----- Cont Structs -----
    struct ContEntity {
        string name;
        uint256 creationTime;
        uint256 lastUpdateTime;
        uint256 initialAPR;
        uint256 buyPrice;
        ContType cType;
    }

    struct AdditionalDataEntity {
        uint256 expireIn;
        uint256 lastUpdated;
        bool isFeeContract;
    }

    struct FullDataEntity {
        string name;
        uint256 creationTime;
        uint256 lastUpdateTime;
        uint256 initialAPR;
        uint256 buyPrice;
        ContType cType;
        uint256 expireIn;
        uint256 lastUpdated;
        bool isFeeContract;
        uint256 reward;
        uint256 claimed;
    }

    struct MonthFeeLog {
        uint256 currentTime;
        bool state;
    }

    // ----- Changes Structs -----
    struct APRChangesEntry {
        uint256 timestamp;
        int256 reducedPercentage;
    }

    // ----- Contract Storage -----
    IterableMapping.Map private contOwners;
    mapping(address => ContEntity[]) private _contsOfUser;
    mapping(ContType => uint256) public contPrice;
    mapping(ContType => uint256) public initRewardAPRPerCont;
    mapping(ContType => APRChangesEntry[]) private aprChangesHistory;
    uint256 public cashoutTimeout;
    uint256 public autoReduceAPRInterval;
    uint256 public autoReduceAPRRate;

    address public admin0XB;
    address public token;

    uint256 public totalContsCreated;

    // ----- Admin Dashboard Variables -----
    mapping(ContType => uint256) private _totalContsPerType;
    mapping(address => mapping(uint256 => bool)) public _brokeevenContract;

    // Adding feature - fee by month
    // using ContEntity[] => cannot update field into ContEntity struct (because using proxy

    IERC20 public feeToken;
    uint256 public decreaseFeePercent;
    bool public isMonthFeeActive = true;
    uint256 public defaultExpireIn;
    mapping(ContType => uint256) public feeInMonth;
    // using mapping instead of array to easy scale with proxy
    mapping(address => mapping(uint256 => AdditionalDataEntity)) public additionalDataContract;
    mapping(uint256 => MonthFeeLog) public monthFeeLogs;
    uint256 public maxIndexMonthFeeLogs;

    // ----- Events -----
    event BreakevenChanged(ContType _cType, uint256 delta);
    event ExtendContract(uint256 index, uint256 time);
    event ChangeMonthFee(ContType _cType, uint256 fee);
    event ChangeFeeToken(address feeToken);
    event ChangeMonthFeeState(bool status);
    event WithdrawFeeToken(address user, uint256 amount);

    // ----- Constructor -----
    function initialize(
        uint256[] memory _contPrices,
        uint256[] memory _rewardAPRs,
        uint256 _cashoutTimeout,
        uint256 _autoReduceAPRRate
    ) public initializer {
        autoReduceAPRInterval = UNIX_YEAR;
        totalContsCreated = 0;
        uint256 initialTstamp = block.timestamp;
        for (uint256 i = 0; i < 3; i++) {
            contPrice[ContType(i)] = _contPrices[i];
            initRewardAPRPerCont[ContType(i)] = _rewardAPRs[i];
            _totalContsPerType[ContType(i)] = 0;
            aprChangesHistory[ContType(i)];
            aprChangesHistory[ContType(i)].push(APRChangesEntry({ timestamp: initialTstamp, reducedPercentage: 0 }));
        }
        cashoutTimeout = _cashoutTimeout;
        admin0XB = msg.sender;
        autoReduceAPRRate = _autoReduceAPRRate;
    }

    // only run after deploy month fee feature
    function setupDataForMonthFee(
        address _feeToken,
        uint256 _tesseractFee,
        uint256 _cubeFee,
        uint256 _squareFee,
        uint256 _defaultExpireIn
    ) external onlyAuthorities {
        feeToken = IERC20(_feeToken);
        feeInMonth[ContType.Tesseract] = _tesseractFee;
        feeInMonth[ContType.Cube] = _cubeFee;
        feeInMonth[ContType.Square] = _squareFee;
        defaultExpireIn = _defaultExpireIn;
        monthFeeLogs[0] = MonthFeeLog(block.timestamp, true);
        maxIndexMonthFeeLogs = 0;
        isMonthFeeActive = true;
    }

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token || msg.sender == admin0XB, "Access Denied!");
        _;
    }

    modifier onlyToken() {
        require(msg.sender == token, "Access Denied!");
        _;
    }

    // ----- External WRITE functions -----
    /**
        @notice change admin of contract
        @param newAdmin address of newAdmin
    */
    function setAdmin(address newAdmin) external onlyAuthorities {
        require(newAdmin != address(0), "zero address");
        admin0XB = newAdmin;
    }

    /**
        @notice set 0xB token Address
        @param token_ new address of 0xB
    */
    function setToken(address token_) external onlyAuthorities {
        require(token_ != address(0), "zero address");
        token = token_;
    }

    /// @notice create new contract storages for account
    /// @param account account of owner
    /// @param contNames list of names of contract
    /// @param _cType type of contract
    function createConts(
        address account,
        string[] memory contNames,
        ContType _cType
    ) external onlyToken {
        _contsOfUser[account];
        uint256 currentAPR = this.currentRewardAPRPerNewCont(_cType);

        for (uint256 i = 0; i < contNames.length; i++) {
            _contsOfUser[account].push(
                ContEntity({
                    name: contNames[i],
                    creationTime: block.timestamp,
                    lastUpdateTime: block.timestamp,
                    buyPrice: contPrice[_cType],
                    initialAPR: currentAPR,
                    cType: _cType
                })
            );
            uint256 index = _contsOfUser[account].length - 1;
            bool _isFeeCont = isFeeContract(account, index);
            additionalDataContract[account][index] = AdditionalDataEntity({
                expireIn: block.timestamp + ADDITION_TIME_FOR_NEW,
                lastUpdated: block.timestamp,
                isFeeContract: _isFeeCont
            });
        }

        contOwners.set(account, _contsOfUser[account].length);
        totalContsCreated += contNames.length;
        _totalContsPerType[_cType] += contNames.length;
    }

    // / @notice reduce chosen cont reward to 0 and return amount of rewards claimed so token contract can send tokens
    // / @param account account of owner
    // / @param _contIndex contract index
    // / @return rewardsTotal total amount of rewards claimed
    function _cashoutContReward(address account, uint256 _contIndex) external onlyToken returns (uint256, ContType) {
        if (isMonthFeeActive) {
            _updateCont(account, _contIndex);
            AdditionalDataEntity memory data = additionalDataContract[account][_contIndex];
            if (data.isFeeContract && data.expireIn < block.timestamp) {
                revert("Need extend contract");
            }
        }
        ContEntity[] storage conts = _contsOfUser[account];
        require(_contIndex >= 0 && _contIndex < conts.length, "CONT: Index Error");
        ContEntity storage cont = conts[_contIndex];
        require(claimable(cont.lastUpdateTime), "CASHOUT ERROR: You have to wait before claiming this cont.");
        uint256 currentTstamp = block.timestamp;
        uint256 rewardCont = contRewardInInterval(cont, cont.lastUpdateTime, currentTstamp);
        cont.lastUpdateTime = currentTstamp;

        if (!_brokeevenContract[account][_contIndex]) {
            if (cont.buyPrice <= contRewardInInterval(cont, cont.creationTime, block.timestamp)) {
                _brokeevenContract[account][_contIndex] = true;
                emit BreakevenChanged(cont.cType, 1);
            }
        }
        return (rewardCont, cont.cType);
    }

    /// @notice reduce all conts reward to 0 and return amount of rewards claimed so token contract can send tokens
    /// @param account account of owner
    /// @return rewardsTotal total amount of rewards claimed
    function _cashoutAllContsReward(address account)
        external
        onlyToken
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        ContEntity[] storage conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        require(contsCount > 0, "CASHOUT ERROR: You don't have conts to cash-out");
        ContEntity storage _cont;
        uint256 rewardsTotal = 0;
        uint256[3] memory typeTotal = [rewardsTotal, rewardsTotal, rewardsTotal];

        uint8[3] memory newBreakeven = [0, 0, 0];

        for (uint256 i = 0; i < contsCount; i++) {
            if (isMonthFeeActive) {
                _updateCont(account, i);
                AdditionalDataEntity memory data = additionalDataContract[account][i];
                if (data.isFeeContract && data.expireIn < block.timestamp) {
                    continue;
                }
            }
            _cont = conts[i];
            uint256 contReward = contRewardInInterval(_cont, _cont.lastUpdateTime, block.timestamp);
            rewardsTotal += contReward;
            typeTotal[uint8(_cont.cType)] += contReward;
            _cont.lastUpdateTime = block.timestamp;

            if (
                !_brokeevenContract[account][i] &&
                _cont.buyPrice <= contRewardInInterval(_cont, _cont.creationTime, block.timestamp)
            ) {
                _brokeevenContract[account][i] = true;
                uint8 ct = uint8(_cont.cType);
                newBreakeven[ct] = newBreakeven[ct] + 1;
            }
        }
        for (uint8 ct = 0; ct < 3; ct++) {
            if (newBreakeven[ct] > 0) {
                emit BreakevenChanged(ContType(ct), newBreakeven[ct]);
            }
        }
        return (rewardsTotal, typeTotal[0], typeTotal[1], typeTotal[2]);
    }

    function extendContract(uint256[] memory time, uint256[] memory indexes) external {
        require(isMonthFeeActive, "MONTH_FEE: Not enable");
        uint256 fee = getExtendContractFee(msg.sender, time, indexes);
        require(feeToken.transferFrom(msg.sender, address(this), fee), "MONTH_FEE: Not valid");

        for (uint256 i = 0; i < indexes.length; ++i) {
            AdditionalDataEntity memory additionData = getExpireIn(msg.sender, indexes[i]);
            require(additionData.isFeeContract, "MONTH_FEE: Not valid type");
            additionData.expireIn += time[i];
            additionData.lastUpdated = block.timestamp;
            additionalDataContract[msg.sender][indexes[i]] = additionData;
            emit ExtendContract(indexes[i], time[i]);
        }
    }

    /**
        @notice change contract price of one type
        @param _cType contract type to change price
        @param newPrice new price per contract (0xB)
    */
    function _changeContPrice(ContType _cType, uint256 newPrice) external onlyAuthorities {
        require(newPrice > 0, "MONTH_FEE: NOT VALID");
        contPrice[_cType] = newPrice;
    }

    /**
        @notice change reward apr of one contract type
        @dev the model of calculating reward requires heavily on reduction percentage. Use reduction percent as
        the input. Negative percentages are allowed (if want to increase APR). 100_000_000 = 100%.
        @param _cType contract type to change APR
        @param reducedPercentage reduction percentage
    */
    function _changeRewardAPRPerCont(ContType _cType, int256 reducedPercentage) external onlyAuthorities {
        require(reducedPercentage < int256(HUNDRED_PERCENT), "REDUCE_RWD: do not reduce more than 100%");
        aprChangesHistory[_cType].push(
            APRChangesEntry({ timestamp: block.timestamp, reducedPercentage: reducedPercentage })
        );
    }

    /// @notice only used when admin makes mistake about APR change: undo last APR change of one type
    /// @param _cType type of contract to pop last change
    function _undoRewardAPRChange(ContType _cType) external onlyAuthorities {
        uint256 changesLength = aprChangesHistory[_cType].length;
        require(changesLength > 1, "UNDO CHANGE: No changes found for cType");
        aprChangesHistory[_cType].pop();
    }

    /**
        @notice change cashout timeout. User cannot claim 2 times in one interval of newTime.
        @param newTime new length of interval
    */
    function _changeCashoutTimeout(uint256 newTime) external onlyAuthorities {
        cashoutTimeout = newTime;
    }

    function changeFeeInMonth(ContType _cType, uint256 _newFee) external onlyAuthorities {
        feeInMonth[_cType] = _newFee;
        emit ChangeMonthFee(_cType, _newFee);
    }

    /**
        @notice change auto APR reduce interval per contract
        @param newInterval new interval
    */
    function _changeAutoReduceAPRInterval(uint256 newInterval) external onlyAuthorities {
        autoReduceAPRInterval = newInterval;
    }

    /**
        @notice change auto APR reduce rate per contract
        @param newRate new reduction rate (100% == 100_000_000)
    */
    function _changeAutoReduceAPRRate(uint256 newRate) external onlyAuthorities {
        autoReduceAPRRate = newRate;
    }

    function changeFeeToken(address _feeToken) external onlyAuthorities {
        feeToken = IERC20(_feeToken);
        emit ChangeFeeToken(_feeToken);
    }

    function changeMonthFeeState(bool _status) external onlyAuthorities {
        require(_status != isMonthFeeActive, "MONTH_FEE: INVALID STATUS");
        isMonthFeeActive = _status;
        maxIndexMonthFeeLogs++;
        monthFeeLogs[maxIndexMonthFeeLogs] = MonthFeeLog(block.timestamp, _status);
        emit ChangeMonthFeeState(_status);
    }

    function withdrawFeeToken(address _user) external onlyAuthorities {
        uint256 amount = feeToken.balanceOf(address(this));
        require(feeToken.transfer(_user, amount), "MONTH_FEE_WITHDRAW: INVALID");
        emit WithdrawFeeToken(_user, amount);
    }

    function _updateCont(address account, uint256 _contIndex) private {
        if (!isFeeContract(account, _contIndex)) {
            return;
        }
        AdditionalDataEntity memory additionalData = getExpireIn(account, _contIndex);
        additionalDataContract[account][_contIndex] = additionalData;
    }

    function _updateAllCont(address account) private {
        ContEntity[] memory listCont = _contsOfUser[account];
        if (listCont.length == 0) {
            return;
        }
        for (uint256 i = 0; i < listCont.length; ++i) {
            _updateCont(account, i);
        }
    }

    // ----- External READ functions -----

    function isExpiredCont(address account, uint256 index) public view returns (bool) {
        AdditionalDataEntity memory additionalData = getExpireIn(account, index);
        if (additionalData.expireIn < block.timestamp && additionalData.isFeeContract) {
            return true;
        }
        return false;
    }

    /**
        @notice calculate initial APR for new contract to display on dApp
        @dev iterate through a list of APR changes in history
        @param _cType contract type to query
        @return result apr of contract type _cType
    */
    function currentRewardAPRPerNewCont(ContType _cType) external view returns (uint256) {
        uint256 changesLength = aprChangesHistory[_cType].length;
        uint256 result = initRewardAPRPerCont[_cType];
        for (uint256 i = 0; i < changesLength; i++) {
            result = reduceByPercent(result, aprChangesHistory[_cType][i].reducedPercentage);
        }
        return result;
    }

    /**
        @notice return number of contract of contract type _cType
        @param _cType contract type to query
        @return res return number of contract for each contract type
    */
    function totalContsPerContType(ContType _cType) external view returns (uint256) {
        return _totalContsPerType[_cType];
    }

    /**
        @notice query if an account is an owner of any contract
        @param account address to query
        @return res true if account is the contract number
    */
    function _isContOwner(address account) external view returns (bool) {
        return isContOwner(account);
    }

    /**
        @notice query total reward amount of an address in every contract
        @dev iterate through every contract. Use `contRewardInInterval` to calculate reward in an interval
        from user last claims to now.
        @param account address to query
        @return rewardAmount total amount of reward available for account, tax included
    */
    function _getRewardAmountOf(address account) external view returns (uint256) {
        if (!isContOwner(account)) return 0;

        uint256 rewardAmount = 0;

        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;

        for (uint256 i = 0; i < contsCount; i++) {
            if (isExpiredCont(account, i)) {
                continue;
            }
            ContEntity memory _cont = conts[i];
            rewardAmount += contRewardInInterval(_cont, _cont.lastUpdateTime, block.timestamp);
        }

        return rewardAmount;
    }

    /**
        @notice query reward amount of one contract
        @dev use `contRewardInInterval` to calculate reward in an interval
        from user last claims to now.
        @param account address to query
        @param _contIndex index of contract in user's list
        @return rewardCont amount of reward available for selected contract
    */
    function _getRewardAmountOfIndex(address account, uint256 _contIndex) external view returns (uint256) {
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 numberOfConts = conts.length;
        require(_contIndex >= 0 && _contIndex < numberOfConts, "CONT: Cont index is improper");
        if (isExpiredCont(account, _contIndex)) {
            return 0;
        }
        ContEntity memory cont = conts[_contIndex];
        uint256 rewardCont = contRewardInInterval(cont, cont.lastUpdateTime, block.timestamp);
        return rewardCont;
    }

    /**
        @notice query claimed amount of an address in every contract
        @dev iterate through every contract. Use `contRewardInInterval` to calculate reward in an interval
        from contract creation time to latest claim.
        @param account address to query
        @return total total amount of reward available for account, tax included
        @return list a packed list of every entries
    */
    function _getClaimedAmountOf(address account) public view returns (uint256 total, string memory list) {
        if (!isContOwner(account)) return (0, "");

        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        total = contRewardInInterval(conts[0], conts[0].creationTime, conts[0].lastUpdateTime);
        list = uint2str(total);
        string memory separator = "#";
        for (uint256 i = 1; i < contsCount; i++) {
            uint256 _claimed;
            ContEntity memory _cont = conts[i];
            _claimed = contRewardInInterval(_cont, _cont.creationTime, _cont.lastUpdateTime);
            total += _claimed;
            list = string(abi.encodePacked(list, separator, uint2str(_claimed)));
        }
    }

    /**
        @notice query claimed amount of one contract
        @dev use `contRewardInInterval` to calculate claimed in an interval
        from contract creationTime to latest claim.
        @param account address to query
        @param _contIndex index of contract in user's list
        @return rewardCont amount of reward available for selected contract
    */
    function _getClaimedAmountOfIndex(address account, uint256 _contIndex) public view returns (uint256 rewardCont) {
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 numberOfConts = conts.length;
        require(_contIndex >= 0 && _contIndex < numberOfConts, "CONT: Cont index is improper");
        ContEntity memory cont = conts[_contIndex];
        rewardCont = contRewardInInterval(cont, cont.creationTime, cont.lastUpdateTime);
    }

    /**
        @notice get the list of contracts name from one owner
        @dev concatenate names into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsNames(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory names = conts[0].name;
        string memory separator = "#";
        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];
            names = string(abi.encodePacked(names, separator, _cont.name));
        }
        return names;
    }

    /**
        @notice get the list of contracts creation time from one owner
        @dev concatenate creation time into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsCreationTime(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory _creationTimes = uint2str(conts[0].creationTime);
        string memory separator = "#";

        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];
            _creationTimes = string(abi.encodePacked(_creationTimes, separator, uint2str(_cont.creationTime)));
        }
        return _creationTimes;
    }

    /**
        @notice get the list of contracts ctypes from one owner
        @dev concate ctypes into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsTypes(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory _types = uint2str(uint256(conts[0].cType));
        string memory separator = "#";

        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(uint256(_cont.cType))));
        }
        return _types;
    }

    /**
        @notice get the list of contracts initial aprs from one owner
        @dev concate initial aprs into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsInitialAPR(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory _types = uint2str(conts[0].initialAPR);
        string memory separator = "#";

        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(_cont.initialAPR)));
        }
        return _types;
    }

    /**
        @notice get the list of contracts current aprs from one owner
        @dev concate current aprs into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsCurrentAPR(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";

        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory _types = uint2str(currentAPRSingleCont(conts[0]));
        string memory separator = "#";

        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];
            _types = string(abi.encodePacked(_types, separator, uint2str(currentAPRSingleCont(_cont))));
        }
        return _types;
    }

    /**
        @notice get the list of contracts available rewards from one owner
        @dev concate available rewards into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsRewardAvailable(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        uint256 currentTstamp = block.timestamp;
        uint256 rewardFirstIndex;
        if (!isExpiredCont(account, 0)) {
            rewardFirstIndex = contRewardInInterval(conts[0], conts[0].lastUpdateTime, currentTstamp);
        }
        string memory _rewardsAvailable = uint2str(rewardFirstIndex);
        string memory separator = "#";
        for (uint256 i = 1; i < contsCount; i++) {
            uint256 reward;
            if (!isExpiredCont(account, i)) {
                reward = contRewardInInterval(conts[i], conts[i].lastUpdateTime, currentTstamp);
            }
            _rewardsAvailable = string(abi.encodePacked(_rewardsAvailable, separator, uint2str(reward)));
        }
        return _rewardsAvailable;
    }

    /**
        @notice get the list of contracts last update times from one owner
        @dev concate last update times into one string, separated by a separator ('#')
        @param account address to query
        @return result a string of concatenated result
    */
    function _getContsLastUpdateTime(address account) external view returns (string memory) {
        if (!isContOwner(account)) return "";
        ContEntity[] memory conts = _contsOfUser[account];
        uint256 contsCount = conts.length;
        ContEntity memory _cont;
        string memory _lastUpdateTimes = uint2str(conts[0].lastUpdateTime);
        string memory separator = "#";

        for (uint256 i = 1; i < contsCount; i++) {
            _cont = conts[i];

            _lastUpdateTimes = string(abi.encodePacked(_lastUpdateTimes, separator, uint2str(_cont.lastUpdateTime)));
        }
        return _lastUpdateTimes;
    }

    /**
        @notice get number of contract from one owner
        @param account address to query
        @return count number of contracts owned by this account
    */
    function _getContNumberOf(address account) public view returns (uint256) {
        return contOwners.get(account);
    }

    function getExtendContractFee(
        address account,
        uint256[] memory time,
        uint256[] memory indexes
    ) public view returns (uint256) {
        require(time.length == indexes.length, "INPUT: INVALID");
        uint256 totalFee;

        for (uint256 i = 0; i < indexes.length; ++i) {
            uint256 index = indexes[i];
            uint256 _time = time[i];
            ContEntity memory cont = _contsOfUser[account][index];
            totalFee += (feeInMonth[cont.cType] * _time) / ONE_MONTH;
        }
        return totalFee;
    }

    // ----- Private/Internal Helpers -----
    /// @notice find first APR change of some type after some timestamp
    /// @dev use binary search to find the required result in a time-sorted structure
    /// @param _cType contract type
    /// @param timestamp timestamp to query
    /// @return index index of the first change after timestamp
    function historyBinarySearch(ContType _cType, uint256 timestamp) private view returns (uint256) {
        uint256 leftIndex = 0;
        uint256 rightIndex = aprChangesHistory[_cType].length;
        while (rightIndex > leftIndex) {
            uint256 mid = (leftIndex + rightIndex) / 2;
            if (aprChangesHistory[_cType][mid].timestamp < timestamp) leftIndex = mid + 1;
            else rightIndex = mid;
        }
        return leftIndex;
    }

    function currentAPRSingleCont(ContEntity memory cont) private view returns (uint256) {
        return contAPRAt(cont, block.timestamp);
    }

    /// @notice calculate APR for a single contract at some timestamp
    /// @dev iterate through APR change log and calculate the APR at that time
    /// @param cont contract entity, which contains all infos of a contract
    /// @param tstamp timestamp to query
    /// @return resultAPR
    function contAPRAt(ContEntity memory cont, uint256 tstamp) private view returns (uint256) {
        uint256 creatime = cont.creationTime;
        ContType cType = cont.cType;
        uint256 resultAPR = cont.initialAPR;
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

    /// @notice calculate reward in an interval
    /// @dev iterate through APR change log and for each APR segment/interval, add up its reward to the result
    /// @param cont contract entity, which contains all infos of a contract
    /// @param leftTstamp left border of the interval
    /// @param rightTstamp right border of the interval
    /// @return result
    function contRewardInInterval(
        ContEntity memory cont,
        uint256 leftTstamp,
        uint256 rightTstamp
    ) private view returns (uint256 result) {
        require(leftTstamp <= rightTstamp, "wrong tstamps params");
        require(leftTstamp >= cont.creationTime, "left tstamps bad");
        ContType _cType = cont.cType;

        uint256 firstUpdateInd = historyBinarySearch(_cType, leftTstamp);
        uint256 lastUpdateInd = historyBinarySearch(_cType, rightTstamp);

        uint256 contBuyPrice = cont.buyPrice;
        uint256 itrAPR = contAPRAt(cont, leftTstamp);
        uint256 itrTstamp = leftTstamp;
        uint256 nextTstamp;
        result = 0;
        uint256 deltaTstamp;
        uint256 creatime = cont.creationTime;
        bool diffInterval;
        for (uint256 index = firstUpdateInd; index < lastUpdateInd; index++) {
            nextTstamp = aprChangesHistory[_cType][index].timestamp;
            diffInterval = (fullIntervalCount(nextTstamp, creatime) != fullIntervalCount(itrTstamp, creatime));
            if (diffInterval) {
                nextTstamp = creatime + autoReduceAPRInterval * (fullIntervalCount(itrTstamp, creatime) + 1);
            }
            deltaTstamp = nextTstamp - itrTstamp;
            itrTstamp = nextTstamp;
            result += (((contBuyPrice * itrAPR) / HUNDRED_PERCENT) * deltaTstamp) / UNIX_YEAR;

            if (diffInterval) {
                itrAPR = reduceByPercent(itrAPR, int256(autoReduceAPRRate));
                index--;
            } else {
                itrAPR = reduceByPercent(itrAPR, aprChangesHistory[_cType][index].reducedPercentage);
            }
        }

        while (itrTstamp != rightTstamp) {
            nextTstamp = rightTstamp;
            diffInterval = (fullIntervalCount(nextTstamp, creatime) != fullIntervalCount(itrTstamp, creatime));
            if (diffInterval) {
                nextTstamp = creatime + autoReduceAPRInterval * (fullIntervalCount(itrTstamp, creatime) + 1);
            }
            deltaTstamp = nextTstamp - itrTstamp;
            itrTstamp = nextTstamp;
            result += (((contBuyPrice * itrAPR) / HUNDRED_PERCENT) * deltaTstamp) / UNIX_YEAR;

            if (diffInterval) {
                itrAPR = reduceByPercent(itrAPR, int256(autoReduceAPRRate));
            }
        }
        return result;
    }

    /// @notice mathematically count number of intervals has passed between 2 tstamps
    /// @param input end timestamp
    /// @param creatime start timestamp
    /// @return result number of intervals between 2 timestamps
    function fullIntervalCount(uint256 input, uint256 creatime) private view returns (uint256) {
        return (input - creatime) / autoReduceAPRInterval;
    }

    /// @notice shows that if a contract is claimmable
    /// @param lastUpdateTime timestamp of last update
    /// @return result true/false
    function claimable(uint256 lastUpdateTime) private view returns (bool) {
        return lastUpdateTime + cashoutTimeout <= block.timestamp;
    }

    /// @notice convert uint256 to string
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

    /// @notice reduce input to a percentage with decimals
    function reduceByPercent(uint256 input, int256 reducePercent) internal pure returns (uint256) {
        uint256 newPercentage = uint256(int256(HUNDRED_PERCENT) - reducePercent);
        return ((input * newPercentage) / HUNDRED_PERCENT);
    }

    /// @notice check if an account is a contract owner
    function isContOwner(address account) private view returns (bool) {
        return contOwners.get(account) > 0;
    }

    function getExpireIn(address user, uint256 index) public view returns (AdditionalDataEntity memory) {
        if (!isFeeContract(user, index)) {
            return AdditionalDataEntity(0, 0, false);
        }
        AdditionalDataEntity memory additionalData = additionalDataContract[user][index];
        if (additionalData.expireIn == 0) {
            additionalData.expireIn = defaultExpireIn;
            additionalData.lastUpdated = defaultExpireIn - ADDITION_TIME_FOR_OLD;
        }
        uint256 totalDelay = 0;
        for (uint256 i = 0; i <= maxIndexMonthFeeLogs; ++i) {
            MonthFeeLog memory log = monthFeeLogs[i];
            if (additionalData.lastUpdated >= log.currentTime) {
                continue;
            }
            if (log.state == true) {
                totalDelay = totalDelay + log.currentTime - additionalData.lastUpdated;
            }
            additionalData.lastUpdated = log.currentTime;
        }

        if (block.timestamp > monthFeeLogs[maxIndexMonthFeeLogs].currentTime) {
            if (isMonthFeeActive == false) {
                totalDelay = totalDelay + block.timestamp - monthFeeLogs[maxIndexMonthFeeLogs].currentTime;
            }
            additionalData.lastUpdated = block.timestamp;
        }

        additionalData.expireIn += totalDelay;
        additionalData.isFeeContract = true;

        return additionalData;
    }

    function getFullDataAllCont(address user) public view returns (FullDataEntity[] memory) {
        ContEntity[] memory listCont = _contsOfUser[user];
        FullDataEntity[] memory fullData = new FullDataEntity[](listCont.length);

        for (uint256 i = 0; i < listCont.length; ++i) {
            ContEntity memory cont = listCont[i];
            AdditionalDataEntity memory additional = getExpireIn(user, i);
            FullDataEntity memory item = FullDataEntity(
                cont.name,
                cont.creationTime,
                cont.lastUpdateTime,
                cont.initialAPR,
                cont.buyPrice,
                cont.cType,
                additional.expireIn,
                additional.lastUpdated,
                additional.isFeeContract,
                contRewardInInterval(cont, cont.lastUpdateTime, block.timestamp),
                _getClaimedAmountOfIndex(user, i)
            );
            fullData[i] = item;
        }
        return fullData;
    }

    function getFullDataCont(address user, uint256 index) public view returns (FullDataEntity memory) {
        ContEntity memory cont = _contsOfUser[user][index];

        AdditionalDataEntity memory additional = getExpireIn(user, index);
        FullDataEntity memory item = FullDataEntity(
            cont.name,
            cont.creationTime,
            cont.lastUpdateTime,
            cont.initialAPR,
            cont.buyPrice,
            cont.cType,
            additional.expireIn,
            additional.lastUpdated,
            additional.isFeeContract,
            contRewardInInterval(cont, cont.lastUpdateTime, block.timestamp),
            _getClaimedAmountOfIndex(user, index)
        );
        return item;
    }

    function isFeeContract(address user, uint256 index) public view returns (bool) {
        ContEntity memory cont = _contsOfUser[user][index];
        return _isFeeContract(cont);
    }

    function _isFeeContract(ContEntity memory cont) internal pure returns (bool) {
        if (cont.cType == ContType.Tesseract || cont.cType == ContType.Cube || cont.cType == ContType.Square) {
            return true;
        }
        return false;
    }
}
