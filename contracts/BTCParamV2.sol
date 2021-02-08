pragma solidity >=0.5.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import './interfaces/IPOWToken.sol';
import "./uniswapv2/UniswapV2OracleLibrary.sol";

contract BTCParamV2 {
    using SafeMath for uint256;

    //是否初始化
    bool internal initialized;
    //合约拥有者
    address public owner;
    //参数设置者
    address public paramSetter;

    //btc区块奖励（wei为单位）
    uint256 public btcBlockRewardInWei;
    //全网难度
    uint256 public btcNetDiff;
    //btc每秒手续费收益（wei为单位）
    uint256 public btcTxFeeRewardPerTPerSecInWei;

    //uniswap BTC——USDT的地址
    address public uniPairAddress;
    //使用uniswap输出的价格1还是价格0
    bool public usePrice0;
    //上一次价格更新的时间
    uint32 public lastPriceUpdateTime;
    //最后累计价格
    uint256 public lastCumulativePrice;
    //最后平均价格
    uint256 public lastAveragePrice;

    //需要监听这些参数的地址
    address[] public paramListeners;

    function initialize(address newOwner, address _paramSetter, uint256 _btcNetDiff, uint256 _btcBlockRewardInWei, address _uniPairAddress, bool _usePrice0) public {
        require(!initialized, "already initialized");
        require(newOwner != address(0), "new owner is the zero address");
        initialized = true;
        owner = newOwner;
        paramSetter= _paramSetter;
        btcBlockRewardInWei = _btcBlockRewardInWei;
        btcNetDiff = _btcNetDiff;

        uniPairAddress = _uniPairAddress;
        usePrice0 = _usePrice0;
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 currentBlockTimestamp) =
        UniswapV2OracleLibrary.currentCumulativePrices(_uniPairAddress);

        lastPriceUpdateTime = currentBlockTimestamp;
        lastCumulativePrice = _usePrice0?price0Cumulative:price1Cumulative;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setParamSetter(address _paramSetter) external onlyOwner {
        require(_paramSetter != address(0), "param setter is the zero address");
        emit ParamSetterChanged(paramSetter, _paramSetter);
        paramSetter = _paramSetter;
    }

    //设置BTC的区块难度
    function setBtcNetDiff(uint256 _btcNetDiff) external onlyParamSetter {
        btcNetDiff = _btcNetDiff;
        notifyListeners();
    }

    //设置BTC的区块奖励
    function setBtcBlockReward(uint256 _btcBlockRewardInWei) external onlyParamSetter {
        btcBlockRewardInWei = _btcBlockRewardInWei;
        notifyListeners();
    }

    //更新BTC的价格
    function updateBtcPrice() external onlyParamSetter {
        _updateBtcPrice();
        notifyListeners();
    }

    function _updateBtcPrice() internal {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 currentBlockTimestamp) =
        UniswapV2OracleLibrary.currentCumulativePrices(uniPairAddress);
        uint256 currentPrice = usePrice0?price0Cumulative:price1Cumulative;

        uint256 timeElapsed = currentBlockTimestamp - lastPriceUpdateTime; // overflow is desired
        if (timeElapsed > 0) {
            lastAveragePrice = currentPrice.sub(lastCumulativePrice).div(timeElapsed);
            lastPriceUpdateTime = currentBlockTimestamp;
            lastCumulativePrice = currentPrice;
        }
    }

    //设置手续费的收益
    function setBtcTxFeeRewardRate(uint256 _btcTxFeeRewardPerTPerSecInWei) external onlyParamSetter {
        btcTxFeeRewardPerTPerSecInWei = _btcTxFeeRewardPerTPerSecInWei;
        notifyListeners();
    }

    //设置手续费的收益并更新BTC的价格
    function setBtcTxFeeRewardRateAndUpdateBtcPrice(uint256 _btcTxFeeRewardPerTPerSecInWei) external onlyParamSetter{
        btcTxFeeRewardPerTPerSecInWei = _btcTxFeeRewardPerTPerSecInWei;
        _updateBtcPrice();
        notifyListeners();
    }

    function addListener(address _listener) external onlyParamSetter {
        for (uint i=0; i<paramListeners.length; i++){
            address listener = paramListeners[i];
            require(listener != _listener, 'listener already added.');
        }
        paramListeners.push(_listener);
    }

    function removeListener(address _listener) external onlyParamSetter returns(bool ){
        for (uint i=0; i<paramListeners.length; i++){
            address listener = paramListeners[i];
            if (listener == _listener) {
                delete paramListeners[i];
                return true;
            }
        }
        return false;
    }

    function notifyListeners() internal {
        for (uint i=0; i<paramListeners.length; i++){
            address listener = paramListeners[i];
            if (listener != address(0)) {
                IPOWToken(listener).updateIncomeRate();
            }
        }
    }

    //BTC收入每T每秒（单位为WEI）
    function btcIncomePerTPerSecInWei() external view returns(uint256){
        //1T的hash算力
        uint256 oneTHash = 10 ** 12;
        //基础难度
        uint256 baseDiff = 2 ** 32;
        uint256 blockRewardRate = oneTHash.mul(btcBlockRewardInWei).div(baseDiff).div(btcNetDiff);
        return blockRewardRate.add(btcTxFeeRewardPerTPerSecInWei);
    }

    //获得BTC价格
    function btcPrice() external view returns (uint256) {
        return lastAveragePrice.mul(100).div(2**112);
    }

    /* ========== MODIFIERS ========== */
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    modifier onlyParamSetter() {
        require(msg.sender == paramSetter, "!paramSetter");
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ParamSetterChanged(address indexed previousSetter, address indexed newSetter);
}