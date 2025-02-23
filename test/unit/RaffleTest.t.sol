//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {console2} from "forge-std/console2.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    address public Player = makeAddr("Aria");
    uint256 public constant STARTING_BALANCE = 1000 ether;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subId;
    uint32 callbackGasLimit;

    event RaffleEntered(address indexed player); //shout out the new player
    event winnerIsSelected(address indexed winner); //shout out the winner
    event RandomWordsRequested(uint256 indexed requestId);

    modifier enterToRaffle() {
        vm.prank(Player);
        // for changing the raffleState to calculating: we should set the upkeepNeeded to true (which accordingly need to a player enter the raffle lottery and the interval should be passed)
        raffle.EnterRaffle{value: entranceFee}(); // enter to the lottery with enough ETH
        // for passing the interval between two period of lottery, we should increase the block.timestamp with a special cheatcode
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.DeployRaffleContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        subId = config.subId;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(Player, STARTING_BALANCE);
    }

    function testRaffleInitizlizesInStateOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertWhenNotEnoughEthToEnter() public {
        vm.prank(Player);
        vm.expectRevert(Raffle.Raffle__notEnoughEthToEnter.selector);
        raffle.EnterRaffle();
    }

    function testRaffleRecordPlayersWhenTheyEnter() public {
        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();
        assert(raffle.getPlayer(0) == Player);
    }

    function testEmitEventWhenPlayerEnterRaffle() public {
        vm.prank(Player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(address(Player));

        raffle.EnterRaffle{value: entranceFee}();
    }

    function testDontallowPlayersEnterWhileRaffleCalculating()
        public
        enterToRaffle
    {
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__raffleNotOpen.selector);
        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepIsFalseWhenItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnFalseWhenRaffleStateIsNotOpen()
        public
        enterToRaffle
    {
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueIfParametersAreGood()
        public
        enterToRaffle
    {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfUpkeepNeededIsTrue() public {
        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 playersLength = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        playersLength = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__upkeepNotNeeded.selector,
                currentBalance,
                playersLength,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        vm.prank(Player);
        raffle.EnterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    function testFullfillRandomWordsCanBeCalledOnlyAfterPerformUpkeep(
        uint256 randomRequestId
    ) public enterToRaffle {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFullfillRandomWordsPickAWinnerResetPlayersAndSendMoney()
        public
        enterToRaffle
    {
        uint256 additionalEntrants = 10;
        uint256 startingIndex = 1;
        address expectedWinner = address(1);

        // Add players to the raffle
        for (
            uint256 i = startingIndex;
            i < additionalEntrants + startingIndex;
            i++
        ) {
            address newPlayer = address(uint160(i));
            hoax(newPlayer, 1 ether);
            raffle.EnterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getlastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Request random words
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        console2.logUint(uint(entries[0].topics[0]));
        bytes32 requestId = entries[1].topics[1];

        // Ensure the requestId is valid
        require(requestId != bytes32(0), "Request ID not found in logs");

        // Log the requestId for debugging
        console2.log("Request ID:", uint256(requestId));

        // Fulfill the random words request
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Check the results
        uint256 endingTimeStamp = raffle.getlastTimeStamp();
        address winner = raffle.getRecentWinner();
        uint256 winnerBalance = winner.balance;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 playersLength = raffle.getPlayersLength();
        uint256 prize = entranceFee * (additionalEntrants + 1);
        uint256 endLotteryBalance = address(raffle).balance;

        assert(winnerBalance == startingBalance + prize - entranceFee);
        assert(uint256(raffleState) == 0);
        assert(winner == expectedWinner);
        assert(endingTimeStamp > startingTimeStamp);
        assert(playersLength == 0);
        assert(endLotteryBalance == 0);
    }
}
