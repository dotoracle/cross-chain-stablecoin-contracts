pragma solidity >=0.8.0;

import "./interfaces/ICrossChainStableCoinLP.sol";
import "./CrossChainStableCoinLP.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StableCoinPair is CrossChainStableCoinLP {
    using SafeMath for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    event AddLiquidity(address indexed sender, uint256 amount0);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        uint256 amount2,
        address indexed to
    );
    event SwapInPair(
        address indexed sender,
        address tokenIn,
        address tokenOut,
        uint256 pair,
        uint256 amountIn,
        uint256 amountOut,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256[] amountIn,
        uint256[] amountOut,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1, uint256 reserve2);

    event PairCreated(
        address indexed token0,
        address indexed token1,
        uint256 pair
    );

    // uint public constant override MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint256 totalPoolValue;
    uint256 public swapFee; /// 0.2% = 20/10000
    uint256 public buyBackTreasury;
    uint256 public totalFee;
    uint256 public constant PERCENTAGE = 10000;
    mapping(address => mapping(address => uint256)) public getPair; // uint256 is index allPairs.length
    uint256[] public allPairs;

    // address public token0;
    // address public token1;
    // address public token2;
    address[] public stableCoinList;
    uint8[] public decimals0;

    // uint8 public decimals0;
    // uint8 public decimals1;
    // uint8 public decimals2;
    bool isEnableBuyBackTreasury;

    // Because decimals may be different from one to the other, so we need convert all to 18 decimals token.

    uint256[3] convertedAmountsOut;

    uint256 private unlocked;
    modifier lock() {
        require(unlocked == 1, "CrossChainStableCoinPool: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "CrossChainStableCoinPool: TRANSFER_FAILED"
        );
    }

    // called once by the factory at time of deployment
    function initialize(
        //uint256 length,
        address[] memory stableCoin
    ) external initializer {
        __DTOUpgradeableBase_initialize();
        __CrossChainStableCoinLP_initialize();
        totalFee = 20;
        buyBackTreasury = 3;
        isEnableBuyBackTreasury = false;
        unlocked = 1;
        // list of stableCoin
        //stableCoin = new address[](length);
        stableCoinList = new address[](stableCoin.length);
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            stableCoinList[i] = stableCoin[i];
        }

        //Decimals of stableCoin
        decimals0 = new uint8[](stableCoin.length);
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            decimals0[i] = IERC20(stableCoinList[i]).decimals();
        }
    }

    function addStableCoinList(address newStableCoin)
        external
        onlyOwner
        returns (bool)
    {
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            require(newStableCoin != stableCoinList[i], "StableCoin exist");
        }
        stableCoinList.push(newStableCoin);
        return true;
    }

    function lockUpStableCoin(address tokenA) public returns (bool) {
        uint256 count = 0;
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            if (tokenA == stableCoinList[i]) {
                count += 1;
            }
        }
        if (count == 0) return false;
        if (count >= 0) return true;
    }

    function viewGetPair(address tokenA, address tokenB)
        public
        view
        returns (uint256)
    {
        return getPair[tokenA][tokenB];
    }

    function enableBuyBackTreasury(bool _isEnableBuyBackTreasury)
        public
        onlyOwner
        returns (bool)
    {
        if (_isEnableBuyBackTreasury != isEnableBuyBackTreasury) {
            isEnableBuyBackTreasury = _isEnableBuyBackTreasury;
        } else {
            return false;
        }
        return true;
    }

    function setTotalFee(uint256 _totalFee) public onlyOwner returns (bool) {
        require(_totalFee <= 30, "Total fee must lower than 0.3 %");
        totalFee = _totalFee;
        calculateFee();
        return true;
    }

    function setBuyBackTreasuryFee(uint256 _buyBackTreasuryFee)
        public
        onlyOwner
        returns (bool)
    {
        require(
            _buyBackTreasuryFee <= 10,
            "Buy back treasury fee must lower than 0.1 %"
        );
        buyBackTreasury = _buyBackTreasuryFee;
        calculateFee();
        return true;
    }

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB)
        external
        onlyOwner
        returns (uint256 pair)
    {
        require(tokenA != tokenB, "TokenA has to differ with TokenB");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        pair = allPairs.length + 1;
        require(token0 != address(0), "Token should be not : ZERO_ADDRESS");
        require(getPair[token0][token1] < 1, "ERROR: PAIR_EXISTS"); // single check is sufficient

        require(
            lockUpStableCoin(tokenA) != false,
            "Token not in stable coin list"
        );
        require(
            lockUpStableCoin(tokenB) != false,
            "Token not in stable coin list"
        );

        // GET index allPairs.length

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair);
    }

    // Calculate SWAP fee (swapFee = totalFee - buybackFee)
    function calculateFee() public returns (uint256) {
        if (isEnableBuyBackTreasury == true) {
            swapFee = totalFee - buyBackTreasury;
            require(
                totalFee == swapFee + buyBackTreasury,
                "error fee calculate"
            );
        } else {
            require(
                isEnableBuyBackTreasury == false,
                "Buy back treasury must be set to false"
            );
            swapFee = totalFee;
        }
        return swapFee;
    }

    function convertTo18Decimals(address _token, uint256 amount)
        public
        view
        returns (uint256)
    {
        return (amount.mul((10**(18 - IERC20(_token).decimals()))));
    }

    function convertFrom18Decimals(address _token, uint256 amount)
        public
        view
        returns (uint256)
    {
        return (amount.div((10**(18 - IERC20(_token).decimals()))));
    }

    function calculatePoolValue() public returns (uint256) {
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            totalPoolValue += IERC20(stableCoinList[i])
                .balanceOf(address(this))
                .mul(10**(18 - IERC20(stableCoinList[i]).decimals()));
        }
        return totalPoolValue;
    }

    function viewPoolValue() public view returns (uint256 _totalPoolValue) {
        _totalPoolValue = totalPoolValue;
        return _totalPoolValue;
    }

    // ADDLIQUIDITY FUNCTION

    function addLiquidity(address _from, uint256[] memory amountsIn)
        external
        returns (uint256)
    {
        require(
            amountsIn.length == stableCoinList.length,
            "input not enough StableCoin list"
        );
        uint256 totalReceivedLP = 0;
        uint256[] memory convertedAmountsIn = new uint256[](
            stableCoinList.length
        );
        // Calculate the input amount to 18 decimals token

        for (uint256 i = 0; i < stableCoinList.length; i++) {
            convertedAmountsIn[i] = convertTo18Decimals(
                stableCoinList[i],
                amountsIn[i]
            );
        }
        // calculate total amount input
        uint256 totalAddIn = 0;
        for (uint256 i = 0; i < amountsIn.length; i++) {
            totalAddIn += convertedAmountsIn[i];
        }

        calculatePoolValue();

        //calculate the total received LP that provider can received
        if (totalSupply == 0) {
            totalReceivedLP = totalAddIn;
        } else {
            totalReceivedLP = totalAddIn.mul(totalSupply).div(totalPoolValue);
        }

        for (uint256 i = 0; i < amountsIn.length; i++) {
            IERC20Upgradeable(stableCoinList[i]).approve(
                address(this),
                amountsIn[i]
            );
            IERC20Upgradeable(stableCoinList[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amountsIn[i]
            );
        }
        // send LP token to provider
        _mint(_from, totalReceivedLP);
        emit AddLiquidity(msg.sender, totalReceivedLP);
        return totalReceivedLP;
    }

    // SWAP stableCoin in a specific PAIR
    function swapInPair(
        address _tokenIn,
        address _tokenOut,
        uint256 pair,
        uint256 _amountIn,
        // uint256 _amountOut,
        address to
    ) external lock {
        // make sure we have enough amount in the pool for withdrawing
        require(getPair[_tokenIn][_tokenOut] == pair, "wrong pair");
        // require(
        //     _amountOut <= IERC20(_tokenOut).balanceOf(address(this)),
        //     "insufficient amount out"
        // );
        require(to != _tokenIn && to != _tokenOut, "INVALID TO ADDRESS");

        uint256 convertedAmountIn;
        uint256 convertedAmountOut;
        // Convert the input amount to 18 decimals token

        // convertedAmountsIn[i] = amountsIn[i].mul(10**(18 - decimals0[i]));
        convertedAmountIn = convertTo18Decimals(_tokenIn, _amountIn);

        // Convert the out amount to 18 decimals token

        //convertedAmountOut = convertTo18Decimals(_tokenOut, _amountOut);

        // Make sure that Output is smaller than Input minus the swapfee

        calculateFee();

        // Calculate AmountOut

        convertedAmountOut =
            convertedAmountIn -
            (convertedAmountIn * totalFee) /
            PERCENTAGE;

        // Convert Amountout to tokenOut's decimals.

        uint256 _amountOut = convertFrom18Decimals(
            _tokenOut,
            convertedAmountOut
        );

        require(
            convertedAmountOut <=
                convertedAmountIn - (convertedAmountIn * totalFee) / PERCENTAGE,
            "insufficient amount in"
        );

        IERC20Upgradeable(_tokenIn).safeTransferFrom(
            msg.sender,
            address(this),
            _amountIn
        );

        //transfer token to recipient

        IERC20Upgradeable(_tokenOut).safeTransfer(to, _amountOut);

        // add swapfee to totalPoolValue
        totalPoolValue =
            totalPoolValue +
            (convertedAmountIn * swapFee) /
            PERCENTAGE;

        emit SwapInPair(
            msg.sender,
            _tokenIn,
            _tokenOut,
            pair,
            _amountIn,
            _amountOut,
            to
        );
    }

    // WITHDRAW LIQUIDITY FUNCTION
    function withdrawLiquidity(
        address _to,
        uint256 totalWithdraw,
        uint256[] memory amountsOut
    ) external returns (bool) {
        // require(
        //     totalWithdraw >= totalIn - (totalIn * totalFee) / PERCENTAGE,
        //     "insufficient amount in"
        // );
        require(
            amountsOut.length == stableCoinList.length,
            "Wrong stablecoin list amount Out "
        );
        uint256 totalMinusLP;
        uint256[] memory convertedAmountsOut = new uint256[](
            stableCoinList.length
        );

        // Calculate the withdraw amount to 18 decimals token
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            convertedAmountsOut[i] = convertTo18Decimals(
                stableCoinList[i],
                amountsOut[i]
            );
        }

        // calculate total amount output
        uint256 totalOut = 0;
        for (uint256 i = 0; i < amountsOut.length; i++) {
            totalOut += convertedAmountsOut[i];
        }
        require(
            totalWithdraw.mul(10**18) >= totalOut,
            "Total withdraw is smaller than total amount out "
        );
        calculatePoolValue();
        // _calculatePoolValue();
        //calculate the total minus LP that withdrawer have to pay
        totalMinusLP = totalOut.mul(totalSupply).div(totalPoolValue);

        // Make sure total withdraw is bigger than to sum of 3 token value the customer want to withdraw
        // require(totalWithdraw >= totalMinusLP);
        // send token to Withdrawer
        for (uint256 i = 0; i < stableCoinList.length; i++) {
            IERC20Upgradeable(stableCoinList[i]).safeTransfer(
                _to,
                amountsOut[i]
            );
        }
        // burn LP after withdrawing
        _burn(msg.sender, totalWithdraw.mul(10**18));
    }
}
