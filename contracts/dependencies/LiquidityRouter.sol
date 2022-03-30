// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

contract LiquidityRouter is Initializable {
    // ----- Router Addresses -----
    IJoeRouter02 private uniswapV2Router;
    address public routerAddress;
    address public uniswapV2Pair;

    // ----- Contract Storage -----
    address public admin0xB;
    address public token;

    // ----- Constructor -----
    function initialize(address _router) public initializer {
        require(_router != address(0), "ROUTER ZERO");
        routerAddress = _router;
        uniswapV2Router = IJoeRouter02(_router);
        admin0xB = msg.sender;
    }

    // ----- Event -----
    event Swapped(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut);

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token || msg.sender == admin0xB, "Access Denied!");
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

    // ----- External WRITE functions -----
    function setToken(address _token) external onlyAuthorities {
        require(_token != address(0), "NEW_TOKEN: zero addr");
        token = _token;
        address _uniswapV2Pair;
        try IJoeFactory(uniswapV2Router.factory()).createPair(token, uniswapV2Router.WAVAX()) {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(token, uniswapV2Router.WAVAX());
        } catch {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(token, uniswapV2Router.WAVAX());
        }
        uniswapV2Pair = _uniswapV2Pair;
    }

    function updateUniswapV2Router(address _newAddr) external onlyAuthorities {
        require(_newAddr != address(uniswapV2Router), "TKN: The router already has that address");
        routerAddress = _newAddr;
        uniswapV2Router = IJoeRouter02(_newAddr);
        address _uniswapV2Pair;
        try IJoeFactory(uniswapV2Router.factory()).createPair(token, uniswapV2Router.WAVAX()) {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(token, uniswapV2Router.WAVAX());
        } catch {
            _uniswapV2Pair = IJoeFactory(uniswapV2Router.factory()).getPair(token, uniswapV2Router.WAVAX());
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
        address[] memory path = getPath(outTokenAddr, false);

        uint256[] memory result = uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            receiver,
            deadline
        );

        emit Swapped(token, amountIn, outTokenAddr, result[result.length - 1]);
    }

    function swap0xBForExactToken(
        address receiver,
        address outTokenAddr,
        uint256 amountOut,
        uint256 amountInMax,
        uint256 deadline
    ) external onlyAuthorities {
        address[] memory path = getPath(outTokenAddr, false);

        uint256[] memory result = uniswapV2Router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            receiver,
            deadline
        );

        uint256 amountInActual = result[0];
        // return residual tokens to sender
        IERC20(token).transfer(receiver, amountInMax - amountInActual);

        emit Swapped(token, amountInActual, outTokenAddr, amountOut);
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

        emit Swapped(inTokenAddr, amountIn, token, result[result.length - 1]);
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

        emit Swapped(inTokenAddr, amountInActual, token, amountOut);
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
                result[1] = token;
            } else {
                result[0] = token;
                result[1] = target;
            }
            return result;
        }

        address[] memory res = new address[](3);
        res[1] = uniswapV2Router.WAVAX();
        if (is0xBOut) {
            res[0] = target;
            res[2] = token;
        } else {
            res[0] = token;
            res[2] = target;
        }
        return res;
    }
}
