// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol";

/**
 * Crypto hunt contract
 */
contract CryptoHunt {

    enum HitStatus { NONE, HIT, CONFIRMED }

    struct Player {
        address payable owner;
        uint256 amount;
        bytes nameEncrypted; // name encripted with private key
        uint256 points;
        mapping(address => HitStatus) hits;
    }

    string public location;

    uint256 public registrationStart;
    uint256 public registrationEnd;
    
    uint256 public gameStart;
    uint256 public gameEnd;
    
    uint256 public minPlayers;
    uint256 public minAmount;
    
    uint256 public totalAmount;
    
    uint256 public hitPoints = 1;
    uint256 public confirmPoints = 2;
    
    address[] public playerAdresses;
    mapping(address => Player) public players;

    /**
     * Registers player with public address (from web - he has corresponding private key for playing)
     */
    function register(address _public, bytes memory _nameEncrypted) payable external {
        
        require(_public != address(0), 'address empty');
        require(players[_public].owner == address(0), 'already registered');
        require(msg.value < minAmount, "<minAmount");
        require(block.timestamp >= registrationStart && block.timestamp < registrationEnd, "registration over");

        playerAdresses.push(_public);
        players[_public].owner = payable(msg.sender);
        players[_public].amount = msg.value;
        players[_public].nameEncrypted = _nameEncrypted;
    }
    
     /**
     * When game is over - calculate winner(s) with most points - can be called once
     */
    function calculateWinners() external {
        require(block.timestamp >= gameEnd, "game not over");
        require(totalAmount == 0, "winners calculated");
        require(playerAdresses.length >= minPlayers, "too few players");
     
        totalAmount = address(this).balance;

        // find winners
        uint256 _maxPoints = 0;
        uint256 _maxCount = 0;
        uint256 _i;
        for (_i = 0; _i < playerAdresses.length; _i++) {
            uint256 _points = players[playerAdresses[_i]].points;
            if (_points > _maxPoints) {
                _maxPoints = _points;
                _maxCount = 1;
            } else {
                _maxCount++;
            }  
        }
        
        // distribute amounts to be claimed
        uint256 _priceAmount = totalAmount / _maxCount;
        for (_i = 0; _i < playerAdresses.length; _i++) {
            uint256 _points = players[playerAdresses[_i]].points;
            if (_points == _maxPoints) {
                players[playerAdresses[_i]].amount = _priceAmount;
            } else {
                players[playerAdresses[_i]].amount = 0;
            }  
        }
    }
    
    /**
     * When registration period is over and not enough players anyone can get refund
     * If game is over used to claim won amounts
     */
    function claim() external {
        
        require(players[msg.sender].amount > 0, 'nothing to claim');
        
        if (playerAdresses.length < minPlayers) {
            require(block.timestamp >= registrationEnd, "registration not over");
        } else {
            require(block.timestamp >= gameEnd, "game not over");
            require(totalAmount > 0, "profits not calculated");
        }
        
        uint256 _amount = players[msg.sender].amount;
        players[msg.sender].amount = 0;
        players[msg.sender].owner.transfer(_amount);
    }
    
    /**
     * When a player hits another one - call this method
     */
    function hit(address _looser, bytes memory _signature) external {
        require(block.timestamp >= gameStart && block.timestamp < gameEnd, "!game active");
        require(players[msg.sender].hits[_looser] == HitStatus.NONE, 'already won');
        require(players[_looser].hits[msg.sender] == HitStatus.NONE, 'already lost');
        
        bytes32 _hash = getHash(_looser);
        address _signer = ECDSA.recover(_hash, _signature);
        require(_signer == _looser, 'invalid signature');
        
        players[msg.sender].hits[_looser] == HitStatus.HIT;
        players[msg.sender].points += hitPoints;
        
    }

    /**
     * The loosing player when called by name confirms hit (fairplay)
     */
    function confirmHit(address _winner, bytes memory _signature) external {
        require(block.timestamp >= gameStart && block.timestamp < gameEnd, "!game active");
        require(players[_winner].hits[msg.sender] == HitStatus.HIT, 'not won');
        
        bytes32 _hash = getHash(_winner);
        address _signer = ECDSA.recover(_hash, _signature);
        require(_signer == _winner, 'invalid signature');
        
        players[_winner].hits[msg.sender] == HitStatus.CONFIRMED;
        players[_winner].points += confirmPoints;
    }
    
    function getHash(address _other) public view returns (bytes32)
    {
        return keccak256(abi.encodePacked(msg.sender, _other));
    }
}
