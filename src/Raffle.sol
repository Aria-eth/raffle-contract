// Order of Layout:

//     Pragma statements
//     Import statements
//     Events
//     Errors
//     Interfaces
//     Libraries
//     Contracts

// Inside each contract, library or interface, use the following order:
// Type declarations
// State variables
// Events
// Errors
// Modifiers
// Functions

// Order of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private

//SPDX-License-Identifier:MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Raffle
 * @author Aria-eth
 * @notice This is for create a sample raffle
 * @dev Implements chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    uint256 private immutable i_EntranceFee;
    /**
     * @dev the time between each round of lottery
     */
    uint256 public immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private s_lastTimeLottery;
    address payable[] private s_players;
    RaffleState private s_RaffleState;
    address private s_recentWinner;

    event RaffleEntered(address indexed player); //shout out the new player
    event winnerIsSelected(address indexed winner); //shout out the winner
    event RandomWordsRequested(uint256 indexed requestId);

    error Raffle__notEnoughEthToEnter();
    error Raffle__notEnoughTimePassed();
    error Raffle__noPlayer();
    error Raffle__transferFailed();
    error Raffle__raffleNotOpen();
    error Raffle__upkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 keyHash,
        uint256 subId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_EntranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = keyHash;
        i_subscriptionId = subId;
        i_callbackGasLimit = callbackGasLimit;
        s_lastTimeLottery = block.timestamp;
        s_RaffleState = RaffleState.OPEN;
    }

    function EnterRaffle() external payable {
        // require(msg.value > i_EntranceFee, "Not enough ETH to enter the raffle");
        // require(msg.value >= i_EntranceFee, Raffle__notEnoughEthToEnter());
        if (msg.value < i_EntranceFee) {
            revert Raffle__notEnoughEthToEnter();
        }
        if (s_RaffleState != RaffleState.OPEN) {
            revert Raffle__raffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    // 1- get a random number, if enough time has passed
    // 2- use that random nuber to pick the winner
    // 3- call that address to pay
    // 4- be automatically called

    // when should the new round of lottery be called (when should the winner be picked?)?
    /**
     * @dev this function is called by chainlink automation to realize when the winner should be picked.
     * the following terms should be true to upkeepNeeded to be true:
     * 1- the time betweeen two round should be passed.
     * 2- there should be at least one player.
     * 3- the raffleState should be open.
     * 4- tha contract has ETH.
     * 5- the subscription has LINK.
     */
    function checkUpkeep(bytes memory /* checkData */ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeLottery) >= i_interval);
        bool hasPlayer = s_players.length > 0;
        bool raffleIsOpen = s_RaffleState == RaffleState.OPEN;
        bool hasEth = address(this).balance > 0;

        upkeepNeeded = timeHasPassed && hasPlayer && raffleIsOpen && hasEth;
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */ ) external {
        // check if enough time has passed
        (bool success,) = checkUpkeep("");
        if (!success) {
            revert Raffle__upkeepNotNeeded(address(this).balance, s_players.length, uint256(s_RaffleState));
        }
        if (s_players.length == 0) {
            revert Raffle__noPlayer();
        }

        s_RaffleState = RaffleState.CALCULATING_WINNER;

        //get a random number from chainlink
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash,
            subId: i_subscriptionId,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: i_callbackGasLimit,
            numWords: NUM_WORDS,
            // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RandomWordsRequested(requestId);
    }

    // what chainlink do, when return numbers
    function fulfillRandomWords(uint256, /* requestId */ uint256[] calldata randomWords) internal override {
            uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable winner = s_players[winnerIndex];
        s_recentWinner = winner;
        s_RaffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeLottery = block.timestamp;
        emit winnerIsSelected(winner);

        (bool success,) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__transferFailed();
        }
    }

    //get function
    function getEntranceFee() public view returns (uint256) {
        return i_EntranceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getPlayersLength() public view returns (uint256) {
        return s_players.length;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_RaffleState;
    }

    function getlastTimeStamp() external view returns(uint256) {
        return s_lastTimeLottery;
    }

    function getRecentWinner() external view returns(address) {
        return s_recentWinner;
    }
}
