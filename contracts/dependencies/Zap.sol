// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";
import "../interfaces/IWNative.sol";

contract Zap is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    struct ProtocolStats {
        address router;
        address factory;
    }

    struct ZapInForm {
        bytes32 protocolType;
        address from;
        uint256 amount;
        address to;
        address receiver;
    }

    struct AddLiquidityAVAXForm {
        address _router;
        uint256 _value;
        address _token;
        address _receiver;
        uint256 _tokenAmount;
    }

    /* ========== CONSTANT VARIABLES ========== */

    address public usdtToken;
    address public wrappedNative;
    address public usdcToken;
    address public zeroXBlockToken;

    /* ========== STATE VARIABLES ========== */

    mapping(bytes32 => ProtocolStats) public protocols; // ex protocol: quickswap, sushiswap

    event ZapIn(address indexed token, address indexed lpToken, uint256 indexed amount, bytes32 protocol);

    event ZapOut(address indexed lpToken, uint256 indexed amount, bytes32 protocol);

    /* ========== INITIALIZER ========== */

    function initialize(
        address _usdtToken,
        address _wrappedNative,
        address _usdcToken
    ) external initializer {
        __Ownable_init();
        require(owner() != address(0), "Zap: owner must be set");

        usdcToken = _usdcToken;
        usdtToken = _usdtToken;
        wrappedNative = _wrappedNative;
    }

    // solhint-disable-next-line
    receive() external payable {}

    /// @notice zap in for token ERC20
    /// @param _params zapIn params
    function zapInToken(ZapInForm calldata _params) public returns (uint256 liquidity) {
        IERC20(_params.from).safeTransferFrom(msg.sender, address(this), _params.amount);
        address router = protocols[_params.protocolType].router;

        _approveTokenIfNeeded(router, _params.from);

        IUniswapV2Pair pair = IUniswapV2Pair(_params.to);
        address token0 = pair.token0();
        address token1 = pair.token1();

        _swapTokenToLPPairToken(_params.protocolType, _params.from, _params.amount, token0, token1, _params.to);
        liquidity = _addLiquidity(
            protocols[_params.protocolType].router,
            token0,
            token1,
            _params.receiver,
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this))
        );
        // send excess amount to msg.sender
        _transferExcessBalance(token0, msg.sender);
        _transferExcessBalance(token1, msg.sender);
    }

    /// @notice zap in ETH to LP
    /// @param _type protocol type
    /// @param _to lp token out
    /// @param _receiver receiver address
    function zapIn(
        bytes32 _type,
        address _to,
        address payable _receiver
    ) external payable {
        uint256 excessNative = _swapETHToLP(_type, _to, msg.value, _receiver);

        // send excess amount to msg.sender
        IUniswapV2Pair pair = IUniswapV2Pair(_to);
        address token0 = pair.token0();
        address token1 = pair.token1();

        _transferExcessBalance(token0, msg.sender);
        _transferExcessBalance(token1, msg.sender);
        _receiver.transfer(excessNative);

        emit ZapIn(wrappedNative, _to, msg.value, _type);
    }

    // @notice zap out LP to token
    /// @param _type protocol type
    /// @param _from lp token in
    /// @param _amount amount LP in
    /// @param _receiver receiver address
    function zapOut(
        bytes32 _type,
        address _from,
        uint256 _amount,
        address _to,
        address _receiver
    ) external {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), _amount);
        address router = protocols[_type].router;
        _approveTokenIfNeeded(router, _from);

        IUniswapV2Pair pair = IUniswapV2Pair(_from);
        address token0 = pair.token0();
        address token1 = pair.token1();
        IJoeRouter02(router).removeLiquidity(token0, token1, _amount, 0, 0, address(this), block.timestamp);

        // convert token 0 -> _to token
        if (token0 != _to) {
            _swap(_type, token0, IERC20(token0).balanceOf(address(this)), _to, _receiver);
            // address[] memory path = new address[](2);
            // path[0] = token0;
            // path[1] = _to;
            // _approveTokenIfNeeded(router, token0);
            // IJoeRouter02(router).swapExactTokensForTokens(
            //     IERC20(token0).balanceOf(address(this)),
            //     0,
            //     path,
            //     _receiver,
            //     block.timestamp
            // );
        }

        if (token1 != _to) {
            _swap(_type, token1, IERC20(token1).balanceOf(address(this)), _to, _receiver);
            // address[] memory path = new address[](2);
            // path[0] = token1;
            // path[1] = _to;
            // _approveTokenIfNeeded(router, token1);
            // IJoeRouter02(router).swapExactTokensForTokens(
            //     IERC20(token1).balanceOf(address(this)),
            //     0,
            //     path,
            //     _receiver,
            //     block.timestamp
            // );
        }

        _transferExcessBalance(_to, _receiver);

        bytes32 protocolType = _type;
        emit ZapOut(_from, _amount, protocolType);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */
    function setToken(address token_) external onlyOwner {
        require(token_ != address(0), "zero address");
        zeroXBlockToken = token_;
    }

    function changeUSDCAddress(address token_) external onlyOwner {
        require(token_ != address(0), "zero address");
        usdcToken = token_;
    }

    function changeUSDTAddress(address token_) external onlyOwner {
        require(token_ != address(0), "zero address");
        usdtToken = token_;
    }

    /// @notice withdraw token that contract hold
    /// @param _token token address
    function withdraw(address _token) external onlyOwner {
        if (_token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(_token).transfer(owner(), IERC20(_token).balanceOf(address(this)));
    }

    // @notice set factory and router for protocol
    /// @param _type protocol type
    /// @param _factory factory address
    /// @param _router router address
    function setFactoryAndRouter(
        bytes32 _type,
        address _factory,
        address _router
    ) external onlyOwner {
        protocols[_type].router = _router;
        protocols[_type].factory = _factory;
    }

    /* ========== Private Functions ========== */

    /// @notice swap ETH to LP token, ETH is MATIC in polygon
    /// @param _type protocol type
    /// @param _lp lp address
    /// @param _amount amount to swap
    /// @param _receiver receiver address
    function _swapETHToLP(
        bytes32 _type,
        address _lp,
        uint256 _amount,
        address _receiver
    ) private returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(_lp);
        address router = protocols[_type].router;
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (token0 == wrappedNative || token1 == wrappedNative) {
            address token = token0 == wrappedNative ? token1 : token0;
            uint256 swapValue = _amount / 2;
            uint256 tokenAmount = _swapETHForToken(_type, token, swapValue, address(this));

            _approveTokenIfNeeded(router, token);
            AddLiquidityAVAXForm memory params;
            params._receiver = _receiver;
            params._router = router;
            params._token = token;
            params._value = _amount - swapValue;
            params._tokenAmount = tokenAmount;
            // (,amountAVAXUsed,) = IJoeRouter02(router).addLiquidityAVAX{ value: _amount - swapValue }(
            //     token,
            //     tokenAmount,
            //     0,
            //     0,
            //     _receiver,
            //     block.timestamp
            // );
            uint256 used = _addLiquidityAVAX(params);
            return _amount - swapValue - used;
        } else {
            uint256 swapValue = _amount / 2;
            uint256 token0Amount = _swapETHForToken(_type, token0, swapValue, address(this));
            uint256 token1Amount = _swapETHForToken(_type, token1, _amount - swapValue, address(this));

            _addLiquidity(router, token0, token1, _receiver, token0Amount, token1Amount);
            // _approveTokenIfNeeded(router, token0);
            // _approveTokenIfNeeded(router, token1);
            // IJoeRouter02(router).addLiquidity(
            //     token0,
            //     token1,
            //     token0Amount,
            //     token1Amount,
            //     0,
            //     0,
            //     _receiver,
            //     block.timestamp
            // );
        }

        return 0;
    }

    function _addLiquidityAVAX(AddLiquidityAVAXForm memory params) private returns (uint256 amountAVAXUsed) {
        (, amountAVAXUsed, ) = IJoeRouter02(params._router).addLiquidityAVAX{ value: params._value }(
            params._token,
            params._tokenAmount,
            0,
            0,
            params._receiver,
            block.timestamp
        );
    }

    /// @notice swap ETH to token, ETH is MATIC in polygon
    /// @param _type protocol type
    /// @param _token token address
    /// @param _value amount to swap
    /// @param _receiver receiver address
    function _swapETHForToken(
        bytes32 _type,
        address _token,
        uint256 _value,
        address _receiver
    ) private returns (uint256) {
        address[] memory path;

        path = new address[](2);
        path[0] = wrappedNative;
        path[1] = _token;

        uint256[] memory amounts = IJoeRouter02(protocols[_type].router).swapExactAVAXForTokens{ value: _value }(
            0,
            path,
            _receiver,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    /// @notice swap token to token
    /// @param _type protocol type
    /// @param _from from token address
    /// @param _amount amount to swap
    /// @param _to to token address
    /// @param _receiver receiver address
    function _swap(
        bytes32 _type,
        address _from,
        uint256 _amount,
        address _to,
        address _receiver
    ) private returns (uint256) {
        // get pair of two token
        address factory = protocols[_type].factory;

        address pair = IJoeFactory(factory).getPair(_from, _to);
        address[] memory path;

        if (pair != address(0)) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[2] = _to;

            if (_hasPair(factory, _from, wrappedNative) && _hasPair(factory, wrappedNative, _to)) {
                path[1] = wrappedNative;
            } else if (_hasPair(factory, _from, usdcToken) && _hasPair(factory, usdcToken, _to)) {
                path[1] = usdcToken;
            } else if (_hasPair(factory, _from, usdtToken) && _hasPair(factory, usdtToken, _to)) {
                path[1] = usdtToken;
            } else if (_hasPair(factory, _from, zeroXBlockToken) && _hasPair(factory, zeroXBlockToken, _to)) {
                path[1] = zeroXBlockToken;
            } else {
                revert("ZAP: NEP"); // not exist path
            }
        }

        _approveTokenIfNeeded(protocols[_type].router, path[0]);
        uint256[] memory amounts = IJoeRouter02(protocols[_type].router).swapExactTokensForTokens(
            _amount,
            0,
            path,
            _receiver,
            block.timestamp
        );
        return amounts[amounts.length - 1];
    }

    /// @notice get key for pair token0 - token1 with key(token0, token1) === key(token1, token0)
    /// @param _token0 token0
    /// @param _token1 token1
    function _getBytes32Key(address _token0, address _token1) private pure returns (bytes32) {
        (_token0, _token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
        return keccak256(abi.encodePacked(_token0, _token1));
    }

    /// @notice approve if needed
    /// @param _spender spender address
    /// @param _token token to approve
    function _approveTokenIfNeeded(address _spender, address _token) private {
        if (IERC20(_token).allowance(address(this), address(_spender)) == 0) {
            IERC20(_token).safeApprove(address(_spender), type(uint256).max);
        }
    }

    /// @notice check is has pair of token0 - token1
    /// @param _factory factory address
    /// @param _token0 token0 address
    /// @param _token1 token1 address
    function _hasPair(
        address _factory,
        address _token0,
        address _token1
    ) private view returns (bool) {
        return IJoeFactory(_factory).getPair(_token0, _token1) != address(0);
    }

    /// @notice transfer excess balance to user, when user call zap func
    /// @param _token token to transfer
    /// @param _user receiver
    function _transferExcessBalance(address _token, address _user) private {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        if (amount > 0) {
            IERC20(_token).safeTransfer(_user, amount);
        }
    }

    function _swapTokenToLPPairToken(
        bytes32 _type,
        address _from,
        uint256 _amount,
        address _token0,
        address _token1,
        address _to
    ) private {
        // IERC20(_from).safeTransferFrom(msg.sender, address(this), _amount);
        // swap half amount for other
        if (_from == _token0 || _from == _token1) {
            address other = _from == _token0 ? _token1 : _token0;
            uint256 sellAmount = _amount / 2;
            _swap(_type, _from, sellAmount, other, address(this));
        } else {
            uint256 sellAmount = _amount / 2;
            _swap(_type, _from, sellAmount, _token0, address(this));
            _swap(_type, _from, _amount - sellAmount, _token1, address(this));
        }
        emit ZapIn(_from, _to, _amount, _type);
    }

    function _addLiquidity(
        address _router,
        address _token0,
        address _token1,
        address _receiver,
        uint256 _token0Amount,
        uint256 _token1Amount
    ) private returns (uint256 liquidity) {
        _approveTokenIfNeeded(_router, _token0);
        _approveTokenIfNeeded(_router, _token1);
        (, , liquidity) = IJoeRouter02(_router).addLiquidity(
            _token0,
            _token1,
            _token0Amount,
            _token1Amount,
            0,
            0,
            _receiver,
            block.timestamp
        );
    }
}
