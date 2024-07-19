// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "solady/tokens/ERC20.sol"; 
import "solady/utils/SafeTransferLib.sol";
import "solady/utils/FixedPointMathLib.sol";

import "./UniswapV2FactoryClone.sol";
import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/IERC3156FlashBorrower.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "forge-std/Test.sol";


contract UniswapV2Pair is ERC20, IERC3156FlashLender {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint256 public kLast;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() {
        factory = msg.sender;
    }

    function name() public view virtual override returns (string memory) {
        return "Uniswap V2";
    }

    function symbol() public view virtual override returns (string memory) {
        return "UNI-V2";
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN");
        token0 = _token0;
        token1 = _token1;
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "UniswapV2: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast; 
        }
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            unchecked {
                // do unchecked
                price0CumulativeLast +=
                    uint256(FixedPointMathLib.mulDiv(uint256(_reserve1), 2 ** 112, uint256(_reserve0))) * timeElapsed;
                price1CumulativeLast +=
                    uint256(FixedPointMathLib.mulDiv(uint256(_reserve0), 2 ** 112, uint256(_reserve1))) * timeElapsed;
            }
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = UniswapV2FactoryClone(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = FixedPointMathLib.sqrt(uint256(_reserve0) * uint256(_reserve1));
                uint256 rootKLast = FixedPointMathLib.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function mint(address to) external lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            liquidity = FixedPointMathLib.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = FixedPointMathLib.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
        }
        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = ERC20(_token0).balanceOf(address(this));
        uint256 balance1 = ERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();
        amount0 = liquidity * balance0 / _totalSupply;
        amount1 = liquidity * balance1 / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _token0.safeTransfer(to, amount0);
        _token1.safeTransfer(to, amount1);
        balance0 = ERC20(_token0).balanceOf(address(this));
        balance1 = ERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * uint256(reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, uint256 deadline) external lock {
        require(block.timestamp <= deadline, "UniswapV2: EXPIRED");
        require(amount0Out > 0 || amount1Out > 0, "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT");
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "UniswapV2: INSUFFICIENT_LIQUIDITY");

        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");

        // Transfer output tokens
        if (amount0Out > 0) _token0.safeTransfer(to, amount0Out);
        if (amount1Out > 0) _token1.safeTransfer(to, amount1Out);

        // Update balances and validate K
        _updateBalancesAndValidateK(_reserve0, _reserve1, amount0Out, amount1Out, to);
    }

    function _updateBalancesAndValidateK(
        uint112 _reserve0,
        uint112 _reserve1,
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) private returns (uint256 amount0In, uint256 amount1In) {
        uint256 balance0 = ERC20(token0).balanceOf(address(this));
        uint256 balance1 = ERC20(token1).balanceOf(address(this));

        amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "UniswapV2: INSUFFICIENT_INPUT_AMOUNT");

        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (1000 ** 2), "UniswapV2: K"
        );
        // Update reserves
        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function sync() external lock {
        _update(ERC20(token0).balanceOf(address(this)), ERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    // Flashloan functionality for ERC3156
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (token == token0 || token == token1) {
            return ERC20(token).balanceOf(address(this));
        }
        return 0;
    }

    // Add flashFee function here
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == token0 || token == token1, "UniswapV2: INVALID_TOKEN");
        return amount * 3 / 1000; // 0.3% fee
    }

    // Move flashLoan function below flashFee function
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        lock
        returns (bool)
    {
        address _token0 = token0;
        address _token1 = token1;
        require(token == _token0 || token == _token1, "UniswapV2: INVALID_TOKEN");

        uint256 fee = flashFee(token, amount);
        uint256 balanceBefore = ERC20(token).balanceOf(address(this));
        token.safeTransfer(address(receiver), amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) == keccak256("ERC3156FlashBorrower.onFlashLoan"),
            "UniswapV2: INVALID_FLASHLOAN_CALLBACK"
        );
        uint256 balanceAfter = ERC20(token).balanceOf(address(this));
        require(balanceAfter >= balanceBefore + fee, "UniswapV2: INSUFFICIENT_FLASHLOAN_REPAYMENT");

        return true;
    }
}
