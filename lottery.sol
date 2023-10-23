//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

contract Lottery {
    address payable public owner;
    uint public entryFee;
    uint public proofTime = 10 seconds;
    uint public hostPercentage;
    address payable[] public players;
    address payable[] public provenPlayers;
    uint public timeEntriesClosed;
    uint public numOfWinners;

    enum State{ LOTTERY_CLOSED, MAKING_ENTRIES, PROVING_ENTRIES, PAYING_OUT}
    State public currentState = State.LOTTERY_CLOSED;

    event EntriesClosed();

    mapping(address => bytes32) public entryHashes;
    mapping(address => uint) public entryValues;
    mapping(address => bool) public winners;

    constructor(uint _entryFee, uint _hostPercentage) {
        owner = payable(msg.sender);
        entryFee = _entryFee;
        hostPercentage = _hostPercentage;
    }

    function setEntryFee(uint _entryFee) public onlyOwner {
        require(currentState == State.LOTTERY_CLOSED, "Can't set the entry fee when the lottery is open");
        entryFee = _entryFee;
    }

    function setProofTime(uint _proofTime) public onlyOwner {
        require(currentState == State.LOTTERY_CLOSED, "Can't set the proof time when the lottery is open");
        proofTime = _proofTime;
    }

    function setHostPercentage(uint _hostPercentage) public onlyOwner{
        require(currentState == State.LOTTERY_CLOSED, "Can't set the host's percentage cut when the lottery is open");
        hostPercentage = _hostPercentage;
    }

    function openLottery() public onlyOwner{
        require(currentState == State.LOTTERY_CLOSED, "Lottery has already been opened");
        currentState = State.MAKING_ENTRIES;
        numOfWinners = 0;
    }

    function playerEntered(address player) public view returns(bool) {
        return(entryHashes[player] != 0);
    }
    
    //Must enter with a value which is a positive integer.
    function makeEntry(bytes32 entryHash) public payable {
        require(currentState == State.MAKING_ENTRIES, "Entries are currently closed");
        require(msg.value >= entryFee, "Message value doesn't cover the entry fee");
        require(!playerEntered(msg.sender), "Player has already entered");
        
        players.push(payable(msg.sender));
        entryHashes[msg.sender] = entryHash;
    }

    function closeEntries() public onlyOwner {
        require(currentState == State.MAKING_ENTRIES, "Entries are already closed");
        emit EntriesClosed();
        timeEntriesClosed = block.timestamp;
        currentState = State.PROVING_ENTRIES;
    }

    struct hStruct {
        uint value;
        address sender;
    }

    function proveEntry(uint value) public {
        require(currentState == State.PROVING_ENTRIES, "Can only prove entry after entries have been closed");
        require(playerEntered(msg.sender), "Player hasn't entered.");
        hStruct memory hashStruct = hStruct(value, msg.sender);
        require(entryHashes[msg.sender] == keccak256(abi.encode(hashStruct.value, hashStruct.sender)), "Value hash did not match");
        require(entryValues[msg.sender] == 0, "Player has already proven their value");

        provenPlayers.push(payable(msg.sender));
        entryValues[msg.sender] = value;
    }

    function pickWinners() internal {
        uint numProvenPlayers = provenPlayers.length;
        uint result = 0;
        for(uint i=0; i<provenPlayers.length; i++) {
            result = result ^ entryValues[provenPlayers[i]];
        }
        uint j = 0;
        for(uint i=0; i<provenPlayers.length; i++) {
            uint playerEntryValue = entryValues[provenPlayers[i]];
            if (result % numProvenPlayers == playerEntryValue % numProvenPlayers) {
                winners[provenPlayers[i]] = true;
                numOfWinners += 1;
                j += 1;
            }
            else {
                winners[provenPlayers[i]] = false;
            }
        }
    }

    // Send 10% of the collected earnings to the host and split the rest amongst the winners
    // Uses the Checks-Effects-Interactions pattern to mitigate against re-entrancy attacks
    function payout() public onlyOwner {
        // Checks
        //require(block.timestamp >= timeEntriesClosed + proofTime, "Not enough time passed to payout");
        require(currentState == State.PROVING_ENTRIES);
        pickWinners();

        // Effects
        closeLottery();

        // Interactions
        owner.transfer(address(this).balance * hostPercentage / 100);
        uint participantReward = 0;
        if (numOfWinners > 0) {
            participantReward = address(this).balance / numOfWinners;
        }
        for(uint i=0; i<numOfWinners; i++) {
            if (winners[provenPlayers[i]]) {
                provenPlayers[i].transfer(participantReward);
            }
        }
        delete provenPlayers; 
    }
    
    function closeLottery() internal {
        currentState = State.LOTTERY_CLOSED;
        for(uint i=0; i<players.length; i++) {
            entryHashes[players[i]] = 0;
            entryValues[players[i]] = 0;
        }
        delete players;
    }

    function getCurrentStateID() public view returns(uint) {
        if (currentState == State.LOTTERY_CLOSED) { return 0; }
        else if (currentState == State.MAKING_ENTRIES) { return 1; }
        else if (currentState == State.PROVING_ENTRIES) { return 2; }
        else { return 3; }
    }

    function getPlayers() public view returns(address payable [] memory) {
        return players;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }
}
