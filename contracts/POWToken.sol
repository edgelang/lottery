pragma solidity >=0.5.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import './interfaces/IStaking.sol';
import './interfaces/IBTCParam.sol';
import './interfaces/ILpStaking.sol';
import './POWERC20.sol';

contract POWToken is POWERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    //是否初始化
    bool internal initialized;
    //合约拥有者
    address public owner;
    //参数设置者
    address public paramSetter;
    //挖矿者
    address public minter;
    //stake质押地址
    address public stakingPool;
    //流动性stake质押地址
    address public lpStakingPool;
    //btcParam合约地址
    address public btcParam;

    //电功率 35000
    uint256 public elecPowerPerTHSec;
    //开始挖矿时间
    uint256 public startMiningTime;

    //电费 58300
    uint256 public electricCharge;
    //矿池手续费率 25000
    uint256 public minerPoolFeeNumerator;
    //折旧率 1000000
    uint256 public depreciationNumerator;
    //
    uint256 public workingRateNumerator;
    //工作hash率 50000
    uint256 public workingHashRate;
    //总共hash率 50000
    uint256 public totalHashRate;
    //上次更新时间
    uint256 public workerNumLastUpdateTime;

    //收入代币 WBTC
    IERC20 public incomeToken;
    //WBTC 利率
    uint256 public incomeRate;
    //奖励代币 MARS
    IERC20 public rewardsToken;
    //MARS利率
    uint256 public rewardRate;
    //奖励代币持续时间 2592000 30days
    uint256 public rewardsDuration;
    //奖励代币完成时间
    uint256 public rewardPeriodFinish;
    //Staking奖励回报率 20
    uint256 public stakingRewardRatio;

    //初始化
    function initialize(string memory name, string memory symbol, address newOwner, address _paramSetter, address _stakingPool, address _lpStakingPool, address _minter, address _btcParam, address _incomeToken, address _rewardsToken, uint256 _elecPowerPerTHSec, uint256 _startMiningTime, uint256 _electricCharge, uint256 _minerPoolFeeNumerator, uint256 _totalHashRate) public {
        require(!initialized, "Token already initialized");
        require(newOwner != address(0), "new owner is the zero address");
        require(_paramSetter != address(0), "_paramSetter is the zero address");
        require(_startMiningTime > block.timestamp, "nonlegal startMiningTime.");
        require(_minerPoolFeeNumerator < 1000000, "nonlegal minerPoolFeeNumerator.");

        initialized = true;
        initializeToken(name, symbol);

        owner = newOwner;
        paramSetter = _paramSetter;
        stakingPool = _stakingPool;
        lpStakingPool = _lpStakingPool;
        minter = _minter;
        btcParam = _btcParam;
        incomeToken = IERC20(_incomeToken);
        rewardsToken = IERC20(_rewardsToken);
        elecPowerPerTHSec = _elecPowerPerTHSec;
        startMiningTime = _startMiningTime;
        electricCharge = _electricCharge;
        minerPoolFeeNumerator = _minerPoolFeeNumerator;
        totalHashRate = _totalHashRate;

        rewardsDuration = 30 days;
        stakingRewardRatio = 20;
        depreciationNumerator = 1000000;
        workingHashRate = _totalHashRate;
        workerNumLastUpdateTime = startMiningTime;
        updateIncomeRate();
    }

    //设置staking奖励率 <=100
    function setStakingRewardRatio(uint256 _stakingRewardRatio) external onlyOwner {
        require(_stakingRewardRatio <= 100, "illegal _stakingRewardRatio");

        updateStakingPoolReward();
        updateLpStakingPoolReward();
        stakingRewardRatio = _stakingRewardRatio;
    }

    //转让合约所有权
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    //改变参数设置者
    function setParamSetter(address _paramSetter) external onlyOwner {
        require(_paramSetter != address(0), "param setter is the zero address");
        emit ParamSetterChanged(paramSetter, _paramSetter);
        paramSetter = _paramSetter;
    }

    function pause() onlyOwner external {
        _pause();
    }

    function unpause() onlyOwner external {
        _unpause();
    }

    //还有多少剩余的算力Token
    function remainingAmount() public view returns(uint256) {
        return totalHashRate.mul(1e18).sub(totalSupply);
    }

    //铸币
    function mint(address to, uint value) external whenNotPaused {
        require(msg.sender == minter, "!minter");
        require(value <= remainingAmount(), "not sufficient supply.");
        _mint(to, value);
        updateLpStakingPoolIncome();
    }

    //增加算力Token总量
    function addHashRate(uint256 hashRate) external onlyParamSetter {
        require(hashRate > 0, "hashRate cannot be 0");

        // should keep current workingRate and incomeRate unchanged.
        totalHashRate = totalHashRate.add(hashRate.mul(totalHashRate).div(workingHashRate));
        workingHashRate = workingHashRate.add(hashRate);
    }

    //设置btcParam地址
    function setBtcParam(address _btcParam) external onlyParamSetter {
        require(btcParam != _btcParam, "same btcParam.");
        btcParam = _btcParam;
        updateIncomeRate();
    }

    //设置开始挖矿时间
    function setStartMiningTime(uint256 _startMiningTime) external onlyParamSetter {
        require(startMiningTime != _startMiningTime, "same startMiningTime.");
        require(startMiningTime > block.timestamp, "already start mining.");
        require(_startMiningTime > block.timestamp, "nonlegal startMiningTime.");
        startMiningTime = _startMiningTime;
        workerNumLastUpdateTime = _startMiningTime;
    }

    //设置电费
    function setElectricCharge(uint256 _electricCharge) external onlyParamSetter {
        require(electricCharge != _electricCharge, "same electricCharge.");
        electricCharge = _electricCharge;
        updateIncomeRate();
    }

    //设置矿池手续费率
    function setMinerPoolFeeNumerator(uint256 _minerPoolFeeNumerator) external onlyParamSetter {
        require(minerPoolFeeNumerator != _minerPoolFeeNumerator, "same minerPoolFee.");
        require(_minerPoolFeeNumerator < 1000000, "nonlegal minerPoolFee.");
        minerPoolFeeNumerator = _minerPoolFeeNumerator;
        updateIncomeRate();
    }

    //设置折旧率
    function setDepreciationNumerator(uint256 _depreciationNumerator) external onlyParamSetter {
        require(depreciationNumerator != _depreciationNumerator, "same depreciationNumerator.");
        require(_depreciationNumerator <= 1000000, "nonlegal depreciation.");
        depreciationNumerator = _depreciationNumerator;
        updateIncomeRate();
    }

    //设置工作hash率
    function setWorkingHashRate(uint256 _workingHashRate) external onlyParamSetter {
        require(workingHashRate != _workingHashRate, "same workingHashRate.");
        //require(totalHashRate >= _workingHashRate, "param workingHashRate not legal.");

        if (block.timestamp > startMiningTime) {
            workingRateNumerator = getHistoryWorkingRate();
            workerNumLastUpdateTime = block.timestamp;
        }

        workingHashRate = _workingHashRate;
        updateIncomeRate();
    }

    //
    function getHistoryWorkingRate() public view returns (uint256) {
        if (block.timestamp > startMiningTime) {
            uint256 time_interval = block.timestamp.sub(workerNumLastUpdateTime);
            uint256 totalRate = workerNumLastUpdateTime.sub(startMiningTime).mul(workingRateNumerator).add(time_interval.mul(getCurWorkingRate()));
            uint256 totalTime = block.timestamp.sub(startMiningTime);

            return totalRate.div(totalTime);
        }

        return 0;
    }

    function getCurWorkingRate() public view  returns (uint256) {
        return 1000000 * workingHashRate / totalHashRate;
    }

    //每秒消耗电量BTC（以wei为单位）
    function getPowerConsumptionBTCInWeiPerSec() public view returns(uint256){
        uint256 btcPrice = IBTCParam(btcParam).btcPrice();
        if (btcPrice != 0) {
            uint256 Base = 1e18;
            uint256 elecPowerPerTHSecAmplifier = 1000;
            uint256 powerConsumptionPerHour = elecPowerPerTHSec.mul(Base).div(elecPowerPerTHSecAmplifier).div(1000);
            uint256 powerConsumptionBTCInWeiPerHour = powerConsumptionPerHour.mul(electricCharge).div(1000000).div(btcPrice);
            return powerConsumptionBTCInWeiPerHour.div(3600);
        }
        return 0;
    }

    //每秒BTC的收入（以wei为单位）
    function getIncomeBTCInWeiPerSec() public view returns(uint256){
        uint256 paramDenominator = 1000000;
        uint256 afterMinerPoolFee = 0;
        {
            uint256 btcIncomePerTPerSecInWei = IBTCParam(btcParam).btcIncomePerTPerSecInWei();
            //减去矿池手续费
            afterMinerPoolFee = btcIncomePerTPerSecInWei.mul(paramDenominator.sub(minerPoolFeeNumerator)).div(paramDenominator);
        }

        uint256 afterDepreciation = 0;
        {
            //减去折旧率
            afterDepreciation = afterMinerPoolFee.mul(depreciationNumerator).div(paramDenominator);
        }

        return afterDepreciation;
    }

    //更新收入利率
    function updateIncomeRate() public {
        //not start mining yet.
        if (block.timestamp > startMiningTime) {
            // update income first.
            updateStakingPoolIncome();
            updateLpStakingPoolIncome();
        }

        uint256 oldValue = incomeRate;

        //compute electric charge.
        uint256 powerConsumptionBTCInWeiPerSec = getPowerConsumptionBTCInWeiPerSec();

        //compute btc income
        uint256 incomeBTCInWeiPerSec = getIncomeBTCInWeiPerSec();

        if (incomeBTCInWeiPerSec > powerConsumptionBTCInWeiPerSec) {
            uint256 targetRate = incomeBTCInWeiPerSec.sub(powerConsumptionBTCInWeiPerSec);
            //工作hash率
            incomeRate = targetRate.mul(workingHashRate).div(totalHashRate);
        }
        //miner close down.
        else {
            incomeRate = 0;
        }

        emit IncomeRateChanged(oldValue, incomeRate);
    }

    //更新staking池子收入
    function updateStakingPoolIncome() internal {
        if (stakingPool != address(0)) {
            IStaking(stakingPool).incomeRateChanged();
        }
    }

    //更新流动性staking池子收入
    function updateLpStakingPoolIncome() internal {
        if (lpStakingPool != address(0)) {
            ILpStaking(lpStakingPool).lpIncomeRateChanged();
        }
    }

    //更新staking池子奖励
    function updateStakingPoolReward() internal {
        if (stakingPool != address(0)) {
            IStaking(stakingPool).rewardRateChanged();
        }
    }

    //更新流动性staking池子奖励
    function updateLpStakingPoolReward() internal {
        if (lpStakingPool != address(0)) {
            ILpStaking(lpStakingPool).lpRewardRateChanged();
        }
    }

    //staking池子的奖励
    function stakingRewardRate() public view returns(uint256) {
        return rewardRate.mul(stakingRewardRatio).div(100);
    }
    //流动性staking池子的奖励（staking池子的4倍）
    function lpStakingRewardRate() external view returns(uint256) {
        uint256 _stakingRewardRate = stakingRewardRate();
        return rewardRate.sub(_stakingRewardRate);
    }

    //同步奖励数值
    function notifyRewardAmount(uint256 reward) external onlyOwner {
        updateStakingPoolReward();
        updateLpStakingPoolReward();

        if (block.timestamp >= rewardPeriodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = rewardPeriodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardsToken.balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "Provided reward too high");

        rewardPeriodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    //领取收入
    function claimIncome(address to, uint256 amount) external {
        require(to != address(0), "to is the zero address");
        require(msg.sender == stakingPool || msg.sender == lpStakingPool, "No permissions");
        incomeToken.safeTransfer(to, amount);
    }

    //领取奖励
    function claimReward(address to, uint256 amount) external {
        require(to != address(0), "to is the zero address");
        require(msg.sender == stakingPool || msg.sender == lpStakingPool, "No permissions");
        rewardsToken.safeTransfer(to, amount);
    }

    //万一Token被卡住，取出token
    function inCaseTokensGetStuck(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    modifier onlyParamSetter() {
        require(msg.sender == paramSetter, "!paramSetter");
        _;
    }

    event IncomeRateChanged(uint256 oldValue, uint256 newValue);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ParamSetterChanged(address indexed previousSetter, address indexed newSetter);
    event RewardAdded(uint256 reward);
}