// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IJoeRouter02.sol";
import "../interfaces/IJoeFactory.sol";

contract LiquidityRouter is Initializable, PaymentSplitterUpgradeable {
    uint256 private constant HUNDRED_PERCENT = 100_000_000;

    // ----- Router Addresses -----
    IJoeRouter02 private uniswapV2Router;
    address public routerAddress;
    address public uniswapV2Pair;

    // ----- Contract Storage -----
    address payable public admin0xB;
    IERC20 private token;
    address public tokenAddress;

    uint256 public swapTaxFee;
    address public swapTaxPool;

    // ----- Constructor -----
    function initialize(
        address _router,
        uint256 _fee,
        address _pool
    ) public initializer {
        require(_router != address(0), "ROUTER ZERO");
        address[] memory payees = new address[](1);
        payees[0] = msg.sender;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 1;
        __PaymentSplitter_init(payees, shares);
        routerAddress = _router;
        uniswapV2Router = IJoeRouter02(_router);
        admin0xB = payable(msg.sender);

        swapTaxFee = _fee;
        swapTaxPool = _pool;
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
    ) public view returns (uint256) {
        address[] memory path = getPath(targetToken, is0xBOut);
        uint256[] memory amountsOut = uniswapV2Router.getAmountsOut(inputAmount, path);
        uint256 result = amountsOut[amountsOut.length - 1];
        result = (result * (HUNDRED_PERCENT - swapTaxFee)) / HUNDRED_PERCENT;
        return result;
    }

    function getInputAmount(
        bool is0xBOut,
        address targetToken,
        uint256 outputAmount
    ) public view returns (uint256) {
        address[] memory path = getPath(targetToken, is0xBOut);
        uint256[] memory amountsIn = uniswapV2Router.getAmountsIn(outputAmount, path);
        uint256 result = amountsIn[0];
        result = (result * (HUNDRED_PERCENT + swapTaxFee)) / HUNDRED_PERCENT;
        return result;
    }

    function wrappedNative() public view returns (address) {
        return uniswapV2Router.WAVAX();
    }

    // ----- External WRITE functions -----
    function updateSwapTaxPool(address payable newPool) external onlyAuthorities {
        require(newPool != address(0), "UPD_WALL: zero addr");
        swapTaxPool = newPool;
    }

    function updateSwapFee(uint256 value) external onlyAuthorities {
        require(value <= HUNDRED_PERCENT, "FEES: swap exceeding 100%");
        swapTaxFee = value;
    }

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

    // Only use to fund wallets
    function swapExact0xBForTokenNoFee(
        address receiver,
        address outTokenAddr,
        uint256 amountIn
    ) external onlyAuthorities {
        if (token.allowance(address(this), routerAddress) < amountIn) {
            token.approve(routerAddress, uint256(2**256 - 1));
        }
        address[] memory path = getPath(outTokenAddr, false);
        uint256[] memory result;
        if (outTokenAddr == uniswapV2Router.WAVAX()) {
            result = uniswapV2Router.swapExactTokensForAVAX(amountIn, 0, path, receiver, block.timestamp);
        } else {
            result = uniswapV2Router.swapExactTokensForTokens(amountIn, 0, path, receiver, block.timestamp);
        }
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

        require(getOutputAmount(false, outTokenAddr, amountIn) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        uint256 fee = (amountIn * swapTaxFee) / HUNDRED_PERCENT;
        token.transfer(swapTaxPool, fee);

        address[] memory path = getPath(outTokenAddr, false);
        uint256[] memory result;
        if (outTokenAddr == uniswapV2Router.WAVAX()) {
            result = uniswapV2Router.swapExactTokensForAVAX(amountIn - fee, amountOutMin, path, receiver, deadline);
        } else {
            result = uniswapV2Router.swapExactTokensForTokens(amountIn - fee, amountOutMin, path, receiver, deadline);
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

        require(getInputAmount(false, outTokenAddr, amountOut) <= amountInMax, "INSUFFICIENT_INPUT_AMOUNT");
        address[] memory path = getPath(outTokenAddr, false);
        uint256[] memory result;
        if (outTokenAddr == uniswapV2Router.WAVAX()) {
            result = uniswapV2Router.swapTokensForExactAVAX(amountOut, amountInMax, path, receiver, deadline);
        } else {
            result = uniswapV2Router.swapTokensForExactTokens(amountOut, amountInMax, path, receiver, deadline);
        }
        uint256 amountInActual = result[0];
        uint256 fee = (amountInActual * swapTaxFee) / HUNDRED_PERCENT;

        // return residual tokens to sender
        token.transfer(swapTaxPool, fee);
        token.transfer(receiver, amountInMax - amountInActual - fee);
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
        require(getOutputAmount(true, inTokenAddr, amountIn) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        uint256 fee = (amountIn * swapTaxFee) / HUNDRED_PERCENT;
        IERC20(inTokenAddr).transfer(swapTaxPool, fee);

        address[] memory path = getPath(inTokenAddr, true);
        uint256[] memory result = uniswapV2Router.swapExactTokensForTokens(
            amountIn - fee,
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
        require(getInputAmount(true, inTokenAddr, amountOut) <= amountInMax, "INSUFFICIENT_INPUT_AMOUNT");
        address[] memory path = getPath(inTokenAddr, true);
        uint256[] memory result = uniswapV2Router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            receiver,
            deadline
        );
        uint256 amountInActual = result[0];
        uint256 fee = (amountInActual * swapTaxFee) / HUNDRED_PERCENT;

        // return residual tokens to sender
        IERC20(inTokenAddr).transfer(swapTaxPool, fee);
        IERC20(inTokenAddr).transfer(receiver, amountInMax - amountInActual - fee);
        emit Swapped(inTokenAddr, amountInActual, tokenAddress, amountOut);
    }

    function swapExactAVAXFor0xB(
        address receiver,
        uint256 amountOutMin,
        uint256 deadline
    ) external payable onlyAuthorities {
        uint256 amountIn = msg.value;
        require(getOutputAmount(true, wrappedNative(), amountIn) >= amountOutMin, "INSUFFICIENT_OUTPUT_AMOUNT");
        uint256 fee = (amountIn * swapTaxFee) / HUNDRED_PERCENT;
        payable(swapTaxPool).transfer(fee);
        address[] memory path = getPath(wrappedNative(), true);
        uint256[] memory result = uniswapV2Router.swapExactAVAXForTokens{ value: amountIn - fee }(
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
        address[] memory path = getPath(wrappedNative(), true);
        uint256[] memory result = uniswapV2Router.swapAVAXForExactTokens{ value: msg.value }(
            amountOut,
            path,
            receiver,
            deadline
        );
        uint256 amountInActual = result[0];
        uint256 fee = (amountInActual * swapTaxFee) / HUNDRED_PERCENT;

        // return residual tokens to sender
        payable(swapTaxPool).transfer(fee);
        payable(receiver).transfer(msg.value - amountInActual - fee);
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
