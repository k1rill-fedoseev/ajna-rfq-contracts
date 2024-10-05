#!/bin/bash

anvil --dump-state ./state &
pid=$!
sleep 1
forge script ./script/DeployMocks.sol --rpc-url http://localhost:8545 --broadcast --unlocked -vvvvv
kill $pid
