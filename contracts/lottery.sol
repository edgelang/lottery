pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

//抽奖合约
contract Lottery {
    //合约拥有者
    address public owner;
    //参与者
    address[] cormorants;
    //已经参与人数
    uint public Count = 0;
    //随机数
    uint nonce = 0;
    //总共参与人数
    uint public PCount;
    // 开始时间
    uint256 public starttime = 1612256400; //utc+8 2021 2-2 17:00:00
    //一等奖
    uint public firstPrize;
    //二等奖
    uint public secondPrize;
    //三等奖
    uint public thirdPrize;

    bool public drawPrize = false;
    //地址对应奖品
    mapping (address => uint) public prizes;

    struct addressInfo {
        address addr;
        string name;
        // time join address
        uint256 joinTime;
    }

    struct rewardInfo {
        address addr;
        string name;
        uint prizes;
    }

    //参与人详细信息集合
    addressInfo[] peoples;

    //参与人对应奖品集合
    rewardInfo[] rewards;
    function initializeParam (uint _firstPrize, uint _secondPrize, uint _thirdPrize, uint _PCount,uint256 _time) public {
        require((_firstPrize + _secondPrize + _thirdPrize) <= _PCount, "params error");
        require(msg.sender == owner, "no owner!");
        for(uint i = 0; i < Count; i ++) {
            prizes[cormorants[i]] = 0;
        }
        firstPrize = _firstPrize;
        secondPrize = _secondPrize;
        thirdPrize = _thirdPrize;
        PCount = _PCount;
        starttime = _time;
        Count = 0;
        drawPrize = false;
        owner = msg.sender;
        delete peoples;
        delete rewards;
        delete cormorants;
    }

    //用户参与
    function luckyDraw(string calldata _name) external {
        require(Count < PCount, "The number of people is full");
        require(drawSituation(msg.sender) == false, "You've been involved");
        require(bytes(_name).length <= 24, "name too long");
        cormorants.push(msg.sender);
        addressInfo memory people;
        people.addr = msg.sender;
        people.name = _name;
        people.joinTime = block.timestamp;
        peoples.push(people);
        Count++;
    }

    //查询用户是否参与
    function drawSituation(address _cormorant) private view returns(bool) {
        bool contains = false;
        for(uint i = 0; i < Count; i++) {
            if (cormorants[i] == _cormorant) {
                contains = true;
            }
        }
        return contains;
    }

    //开三等奖
    function _openThirdPrize() private {
        // require(msg.sender == owner, "no owner!");
        for(uint i = thirdPrize; i > 0; i--) {
            address winner = cormorants[winnerNumber()];
            if  (prizes[winner] != 0) {
                i++;
            } else {
                prizes[winner] = 3;
                rewardInfo memory reward;
                reward.addr = winner;
                reward.prizes = 3;
                for(uint j = 0; j < Count; j ++) {
                    if (peoples[j].addr == winner) {
                        reward.name = peoples[j].name;
                    }
                }
                rewards.push(reward);
            }
        }
    }

    //开二等奖
    function _openSecondPrize() private {
        // require(msg.sender == owner, "no owner!");
        for(uint i = secondPrize; i > 0; i--) {
            address winner = cormorants[winnerNumber()];
            if (prizes[winner] != 0) {
                i++;
            } else {
                prizes[winner] = 2;
                rewardInfo memory reward;
                reward.addr = winner;
                reward.prizes = 2;
                for(uint j = 0; j < Count; j ++) {
                    if (peoples[j].addr == winner) {
                        reward.name = peoples[j].name;
                    }
                }
                rewards.push(reward);
            }
        }
    }

    //开一等奖
    function _openFirstPrize() private {
        for(uint i = firstPrize; i > 0; i--) {
            address winner = cormorants[winnerNumber()];
            if (prizes[winner] != 0) {
                i++;
            } else {
                prizes[winner] = 1;
                rewardInfo memory reward;
                reward.addr = winner;
                reward.prizes = 1;
                for(uint j = 0; j < Count; j ++) {
                    if (peoples[j].addr == winner) {
                        reward.name = peoples[j].name;
                    }
                }
                rewards.push(reward);
            }
        }
    }

    function openPrize() external {
        require(msg.sender == owner, "no owner!");
        require(Count >= (PCount - thirdPrize), "There are not enough people");
        require(block.timestamp > starttime, "not start");
        require(drawPrize == false);
        thirdPrize = (thirdPrize + Count) - PCount;
        _openFirstPrize();
        _openSecondPrize();
        _openThirdPrize();
        drawPrize = true;
    }

    // function openthirdPrize() public {
    //     require(msg.sender == owner, "no owner!");
    //     require(Count == PCount, "There are not enough people");
    //     _openthirdPrize();
    // }

    // function opensecondPrize() public {
    //     require(msg.sender == owner, "no owner!");
    //     require(Count == PCount, "There are not enough people");
    //     _opensecondPrize();
    // }

    // function openfirstPrize() public {
    //     require(msg.sender == owner, "no owner!");
    //     require(Count == PCount, "There are not enough people");
    //     _openfirstPrize();
    // }

    // function getPrize() public view returns (int[] memory) {
    //     int[20] memory Prize;
    //     for(uint i = 0; i < PCount; i++) {
    //         Prize[i] = prizes[cormorants[i]];
    //     }
    // }

    //获得所有参与地址
    function getAddress() public view returns (address[] memory) {
        return cormorants;
    }

    //获得参与地址信息集合
    function getAddressInfo() public view returns (addressInfo[] memory) {
        return peoples;
    }

    //获得参与地址获得奖品集合
    function getRewardInfo() public view returns (rewardInfo[] memory) {
        return rewards;
    }
    //产生随机数
    function winnerNumber() private returns(uint) {
        uint winner = uint(keccak256(abi.encodePacked(now, msg.sender, nonce))) % Count;
        nonce++;
        return winner;
    }

    constructor (uint _firstPrize, uint _secondPrize, uint _thirdPrize, uint _PCount) public {
        require((_firstPrize + _secondPrize + _thirdPrize) <= _PCount, "params error");
        firstPrize = _firstPrize;
        secondPrize = _secondPrize;
        thirdPrize = _thirdPrize;
        PCount = _PCount;
        owner = msg.sender;
    }
}