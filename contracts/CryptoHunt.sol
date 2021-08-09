// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/cryptography/ECDSA.sol";

/**
 * Crypto hunt contract
 */
contract CryptoHunt {

    enum HitStatus { NONE, HIT, CONFIRMED }

    struct Player {
        address payable owner;
        uint256 amount; // amount paid / claimable
        bytes nameEncrypted; // name AES encripted with private key
        uint256 protectedUntil; // timestamp for protection period
        uint256 points; // sum of points
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
    uint256 public protectionSeconds = 300; // 5mins after hit - to confirm and continue
    
    address[] public playerAdresses;
    mapping(address => Player) public players;

    /**
     * Deploys new game with configuration
     */
    constructor(string memory _location, uint256 _rS, uint256 _rE, uint256 _gS, uint256 _gE, uint256 _minPlayers, uint256 _minAmount) {
        location = _location;
        registrationStart = _rS;
        registrationEnd = _rE;
        gameStart = _gS;
        gameEnd = _gE;
        minPlayers = _minPlayers;
        minAmount = _minAmount;
    }

    /**
     * Registers player with public address (from web - he has corresponding private key for playing)
     */
    function register(address _public, bytes memory _nameEncrypted) payable external {
                
        require(_public != address(0), 'address empty');

        Player storage _player = players[msg.sender];

        require(_player.owner == address(0), 'already registered');
        require(msg.value < minAmount, "<minAmount");
        require(block.timestamp >= registrationStart && block.timestamp < registrationEnd, "registration over");

        playerAdresses.push(_public);

        _player.owner = payable(msg.sender);
        _player.amount = msg.value;
        _player.nameEncrypted = _nameEncrypted;
    }
    
     /**
     * When game is over - calculate winner(s) with most points - can be called once
     */
    function calculateWinners() external {
        require(block.timestamp >= gameEnd, "game not over");
        require(totalAmount == 0, "already calculated");

        uint256 _playerCount = playerAdresses.length;

        require(_playerCount >= minPlayers, "too few players");
     
        totalAmount = address(this).balance;

        // find winners
        uint256 _maxPoints = 0;
        uint256 _maxCount = 0;
        uint256 _i;
        for (_i = 0; _i < _playerCount; _i++) {
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
        for (_i = 0; _i < _playerCount; _i++) {
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
        
        Player storage _player = players[msg.sender];

        require(_player.amount > 0, 'nothing to claim');
        
        if (playerAdresses.length < minPlayers) {
            require(block.timestamp >= registrationEnd, "registration not over");
        } else {
            require(block.timestamp >= gameEnd, "game not over");
            require(totalAmount > 0, "profits not calculated");
        }
        
        uint256 _amount = _player.amount;
        _player.amount = 0;
        _player.owner.transfer(_amount);
    }
    
    /**
     * When a player hits another one - call this method
     */
    function hit(address _looser, bytes memory _signature) external {
        require(block.timestamp >= gameStart && block.timestamp < gameEnd, "!game active");

        Player storage _player = players[msg.sender];
        Player storage  _looserPlayer = players[_looser];

        require(_player.hits[_looser] == HitStatus.NONE, 'already won');
        require(_looserPlayer.hits[msg.sender] == HitStatus.NONE, 'already lost');
        require(_player.protectedUntil < block.timestamp, 'protected');
        require(_looserPlayer.protectedUntil < block.timestamp, 'protected');
        
        bytes32 _hash = getHash(_looser);
        address _signer = ECDSA.recover(_hash, _signature);
        require(_signer == _looser, 'invalid signature');
        
        _player.hits[_looser] == HitStatus.HIT;
        _player.points += hitPoints;

        // players are protected for a certain time after hit
        _player.protectedUntil = block.timestamp + protectionSeconds;
        _looserPlayer.protectedUntil = block.timestamp + protectionSeconds;
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
    
    /**
    * Gets hash to calculate signature on (with _other players private key)
    */
    function getHash(address _other) public view returns (bytes32)
    {
        return keccak256(abi.encodePacked(msg.sender, _other));
    }
}
