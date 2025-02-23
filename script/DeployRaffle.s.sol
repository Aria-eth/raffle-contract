//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {
        DeployRaffleContract();
    }

    function DeployRaffleContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        if (config.subId == 0) {
            // create a subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (uint256 subId, address vrfCoordinator) = createSubscription.createSubscription(config.vrfCoordinator);
            config.subId = subId;
            config.vrfCoordinator = vrfCoordinator;

            //Fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(config.vrfCoordinator, config.subId, config.link);
        }

        vm.startBroadcast();
        Raffle raffle = new Raffle(
            config.entranceFee,
            config.interval,
            config.vrfCoordinator,
            config.keyHash,
            config.subId,
            config.callbackGasLimit
        );
        vm.stopBroadcast();

        //add consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(raffle), config.vrfCoordinator, config.subId);
        return (raffle, helperConfig);
    }
}
