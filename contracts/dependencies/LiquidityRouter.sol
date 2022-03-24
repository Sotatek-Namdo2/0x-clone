// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
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

    // ----- Modifier (filter) -----
    modifier onlyAuthorities() {
        require(msg.sender == token || msg.sender == admin0xB, "Access Denied!");
        _;
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

    function swapExactTokenFor0xB(
        address outTokenAddr,
        address receiver,
        uint256 amountIn
    ) public {
        address[] memory path = new address[](3);
        path[0] = outTokenAddr;
        path[1] = uniswapV2Router.WAVAX();
        path[2] = token;

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0, // accept any amount of USDC
            path,
            receiver,
            block.timestamp
        );
    }

    function swapExact0xBForToken(
        address outTokenAddr,
        address receiver,
        uint256 amountIn
    ) public {
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = uniswapV2Router.WAVAX();
        path[2] = outTokenAddr;

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0, // accept any amount of USDC
            path,
            receiver,
            block.timestamp
        );
    }

    // ----- External READ functions -----
    function getOutputAmount(address targetToken, uint256 inputAmount) external view returns (uint256[] memory) {
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = uniswapV2Router.WAVAX();
        path[2] = targetToken;

        return uniswapV2Router.getAmountsOut(inputAmount, path);
    }

    function getInputAmount(address inputToken, uint256 outputAmount) external view returns (uint256[] memory) {
        address[] memory path = new address[](3);
        path[0] = inputToken;
        path[1] = uniswapV2Router.WAVAX();
        path[2] = token;

        return uniswapV2Router.getAmountsIn(outputAmount, path);
    }

    // ----- Private/Internal Helpers -----
}
