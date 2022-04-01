// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

contract LiquidityRouter is Initializable, PaymentSplitterUpgradeable {
    // ----- Router Addresses -----
    IJoeRouter02 private uniswapV2Router;
    address public routerAddress;
    address public uniswapV2Pair;

    // ----- Contract Storage -----
    address payable public admin0xB;
    IERC20 private token;
    address public tokenAddress;

    // ----- Constructor -----
    function initialize(address _router) public initializer {
        require(_router != address(0), "ROUTER ZERO");
        address[] memory payees = new address[](1);
        payees[0] = msg.sender;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        __PaymentSplitter_init(payees, shares);
        routerAddress = _router;
        uniswapV2Router = IJoeRouter02(_router);
        admin0xB = payable(msg.sender);
    }

    // ----- Event -----
    event Swapped(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);
    event SwappedNative(uint256 amountIn, address tokenOut, uint256 amountOut);

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == tokenAddress || msg.sender == admin0xB, "Access Denied!");
        _;
    }

    // ----- External READ functions -----
    function getOutputAmount(
        bool is0xBOut,
        address targetToken,
        uint256 inputAmount
    ) external view returns (uint256[] memory) {
        address[] memory path = getPath(targetToken, is0xBOut);
        return uniswapV2Router.getAmountsOut(inputAmount, path);
    }

    function getInputAmount(
        bool is0xBOut,
        address targetToken,
        uint256 outputAmount
    ) external view returns (uint256[] memory) {
        address[] memory path = getPath(targetToken, is0xBOut);
        return uniswapV2Router.getAmountsIn(outputAmount, path);
    }

    function wrappedNative() external view returns (address) {
        return uniswapV2Router.WAVAX();
    }

    // ----- External WRITE functions -----
    function setToken(address _token) external onlyAuthorities {
        require(_token != address(0), "NEW_TOKEN: zero addr");
        tokenAddress = _token;
        token = IERC20(_token);
        address _uniswapV2Pair;
        try IJoeFactory(uniswapV2Router.factory()).createPair(tokenAddress, uniswapV2Router.WAVAX()) {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(tokenAddress, uniswapV2Router.WAVAX());
        } catch {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(tokenAddress, uniswapV2Router.WAVAX());
        }
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateUniswapV2Router(address _newAddr) external onlyAuthorities {
        require(_newAddr != address(uniswapV2Router), "TKN: The router already has that address");
        routerAddress = _newAddr;
        uniswapV2Router = IJoeRouter02(_newAddr);
        address _uniswapV2Pair;
        try IJoeFactory(uniswapV2Router.factory()).createPair(tokenAddress, uniswapV2Router.WAVAX()) {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(tokenAddress, uniswapV2Router.WAVAX());
        } catch {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(tokenAddress, uniswapV2Router.WAVAX());
        }
        uniswapV2Pair = _uniswapV2Pair;
    }

    function swapExact0xBForToken(
        address receiver,
        address outTokenAddr,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external onlyAuthorities {
        if (token.allowance(address(this), routerAddress) < amountIn) {
            token.approve(routerAddress, uint256(2**256 - 1));
        }
        address[] memory path = getPath(outTokenAddr, false);
        uint256[] memory result;
        if (outTokenAddr == uniswapV2Router.WAVAX()) {
            result = uniswapV2Router.swapExactTokensForAVAX(amountIn, amountOutMin, path, receiver, deadline);
        } else {
            result = uniswapV2Router.swapExactTokensForTokens(amountIn, amountOutMin, path, receiver, deadline);
        }
        emit Swapped(tokenAddress, amountIn, outTokenAddr, result[result.length - 1]);
    }

    function swap0xBForExactToken(
        address receiver,
        address outTokenAddr,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 deadline
    ) external onlyAuthorities {
        if (token.allowance(address(this), routerAddress) < amountInMax) {
            token.approve(routerAddress, uint256(2**256 - 1));
        }
        address[] memory path = getPath(outTokenAddr, false);
        uint256[] memory result;
        if (outTokenAddr == uniswapV2Router.WAVAX()) {
            result = uniswapV2Router.swapTokensForExactAVAX(amountOut, amountInMax, path, receiver, deadline);
        } else {
            result = uniswapV2Router.swapTokensForExactTokens(amountOut, amountInMax, path, receiver, deadline);
        }
        uint256 amountInActual = result[0];
        // return residual tokens to sender
        token.transfer(receiver, amountInMax - amountInActual);
        emit Swapped(tokenAddress, amountInActual, outTokenAddr, amountOut);
    }

    function swapExactTokenFor0xB(
        address receiver,
        address inTokenAddr,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external onlyAuthorities {
        if (IERC20(inTokenAddr).allowance(address(this), routerAddress) < amountIn) {
            approveTokenAccess(inTokenAddr);
        }
        address[] memory path = getPath(inTokenAddr, true);
        uint256[] memory result = uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            receiver,
            deadline
        );
        emit Swapped(inTokenAddr, amountIn, tokenAddress, result[result.length - 1]);
    }

    function swapTokenForExact0xB(
        address receiver,
        address inTokenAddr,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 deadline
    ) external onlyAuthorities {
        if (IERC20(inTokenAddr).allowance(address(this), routerAddress) < amountInMax) {
            approveTokenAccess(inTokenAddr);
        }
        address[] memory path = getPath(inTokenAddr, true);
        uint256[] memory result = uniswapV2Router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            receiver,
            deadline
        );
        uint256 amountInActual = result[0];
        // return residual tokens to sender
        IERC20(inTokenAddr).transfer(receiver, amountInMax - amountInActual);
        emit Swapped(inTokenAddr, amountInActual, tokenAddress, amountOut);
    }

    function swapExactAVAXFor0xB(
        address receiver,
        uint256 amountOutMin,
        uint256 deadline
    ) external payable onlyAuthorities {
        uint256 amountIn = msg.value;
        address[] memory path = getPath(this.wrappedNative(), true);
        uint256[] memory result = uniswapV2Router.swapExactAVAXForTokens{ value: amountIn }(
            amountOutMin,
            path,
            receiver,
            deadline
        );
        emit SwappedNative(amountIn, tokenAddress, result[result.length - 1]);
    }

    function swapAVAXForExact0xB(
        address receiver,
        uint256 amountOut,
        uint256 deadline
    ) external payable onlyAuthorities {
        // uint256 amountInMax = msg.value;
        address[] memory path = getPath(this.wrappedNative(), true);
        uint256[] memory result = uniswapV2Router.swapAVAXForExactTokens{ value: msg.value }(
            amountOut,
            path,
            receiver,
            deadline
        );
        uint256 amountInActual = result[0];
        // return residual tokens to sender
        // payable(receiver).transfer(msg.value - amountInActual);
        emit SwappedNative(amountInActual, tokenAddress, amountOut);
    }

    // ----- Private/Internal Helpers -----
    function approveTokenAccess(address tokenAddr) internal {
        IERC20 targetToken = IERC20(tokenAddr);
        targetToken.approve(routerAddress, uint256(2**256 - 1));
    }

    function getPath(address target, bool is0xBOut) internal view returns (address[] memory) {
        if (target == uniswapV2Router.WAVAX()) {
            address[] memory result = new address[](2);

            if (is0xBOut) {
                result[0] = target;
                result[1] = tokenAddress;
            } else {
                result[0] = tokenAddress;
                result[1] = target;
            }
            return result;
        }

        address[] memory res = new address[](3);
        res[1] = uniswapV2Router.WAVAX();
        if (is0xBOut) {
            res[0] = target;
            res[2] = tokenAddress;
        } else {
            res[0] = tokenAddress;
            res[2] = target;
        }
        return res;
    }
}
