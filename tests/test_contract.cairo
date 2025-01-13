use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait};

use unogame::IUnoGameDispatcher;
use unogame::IUnoGameDispatcherTrait;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

#[test]
fn test_create_game() {
    // Deploy contract
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    // Set up test account
    let creator = starknet::contract_address_const::<0x123>();

    // Create game
    let game_id = dispatcher.create_game(creator);

    // Check game state
    let (is_active, current_player_index, _, turn_count, direction_clockwise, is_started) = 
        dispatcher.get_game_state(game_id);

    assert(game_id == 1, 'Game ID should be 1');
    assert(is_active == true, 'Game should be active');
    assert(current_player_index == 0, 'Should start at player 0');
    assert(turn_count == 0, 'Should start at turn 0');
    assert(direction_clockwise == true, 'Should be clockwise');
    assert(is_started == false, 'Should not be started');
}

#[test]
fn test_join_game() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator = starknet::contract_address_const::<0x123>();
    let player2 = starknet::contract_address_const::<0x456>();

    let game_id = dispatcher.create_game(creator);
    dispatcher.join_game(game_id, player2);

    let (is_active, _, _, _, _, is_started) = dispatcher.get_game_state(game_id);
    assert(is_active == true, 'Game should be active');
    assert(is_started == false, 'Game should not be started');
}

#[test]
fn test_start_game() {
    // Deploy contract
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    // Create test accounts
    let creator = starknet::contract_address_const::<1>();
    let player2 = starknet::contract_address_const::<2>();

    // Create and setup game
    let game_id = dispatcher.create_game(creator);
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, creator);  // Add third player to meet minimum requirement
    
    // Start game
    dispatcher.start_game(game_id);

    // Verify game state
    let (is_active, _, _, _, _, is_started) = dispatcher.get_game_state(game_id);
    assert(is_active == true, 'Game should be active');
    assert(is_started == true, 'Game should be started');
}

#[test]
#[should_panic(expected: ('Game already started',))]
fn test_cannot_start_twice() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator = starknet::contract_address_const::<1>();
    let player2 = starknet::contract_address_const::<2>();
    let player3 = starknet::contract_address_const::<3>();

    let game_id = dispatcher.create_game(creator);
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, player3);
    
    dispatcher.start_game(game_id);
    dispatcher.start_game(game_id);  // Should panic
}

#[test]
fn test_multiple_games() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator1 = starknet::contract_address_const::<1>();
    let creator2 = starknet::contract_address_const::<2>();

    let game1_id = dispatcher.create_game(creator1);
    let game2_id = dispatcher.create_game(creator2);

    assert(game1_id != game2_id, 'Game IDs should be different');
    assert(game2_id == game1_id + 1, 'Game ID should increment');

    let active_games = dispatcher.get_active_games();
    assert(*active_games.at(0) == game1_id, 'First game should be active');
    assert(*active_games.at(1) == game2_id, 'Second game should be active');
}

#[test]
fn test_submit_action() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    // Create test accounts
    let creator = starknet::contract_address_const::<1>();
    let player2 = starknet::contract_address_const::<2>();

    // Create and setup game
    let game_id = dispatcher.create_game(creator);
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, creator);
    dispatcher.start_game(game_id);

    dispatcher.submit_action(game_id, 12345, player2);

    let (_, _, _, turn_count, _, _) = dispatcher.get_game_state(game_id);
    assert(turn_count == 1, 'Turn count should be 1');
}

#[test]
fn test_end_game() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator = starknet::contract_address_const::<1>();
    let player2 = starknet::contract_address_const::<2>();
    let player3 = starknet::contract_address_const::<3>();

    // Create game 
    let game_id = dispatcher.create_game(creator);
    
    // Add players
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, player3);
    
    // Start game (needed to maintain proper turn order)
    dispatcher.start_game(game_id);
    
    // End game with creator (who should be the current player)
    dispatcher.end_game(game_id, player2);

    // Verify game ended
    let (is_active, _, _, _, _, _) = dispatcher.get_game_state(game_id);
    assert(is_active == false, 'Game should be ended');
    
}

#[test]
fn test_game_flow() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator = starknet::contract_address_const::<0x123>();
    let player2 = starknet::contract_address_const::<0x456>();
    let player3 = starknet::contract_address_const::<0x789>();

    // Create and setup game
    let game_id = dispatcher.create_game(creator);
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, player3);

    // Start game and submit actions
    dispatcher.start_game(game_id);
    
   
    
    // Player2's turn
    dispatcher.submit_action(game_id, 67890, player2);
    
    // Player3's turn
    dispatcher.submit_action(game_id, 11111, player3);

     // Player2's turn
    dispatcher.submit_action(game_id, 267890, player2);
    
    // Back to creator's turn - can end game now
    dispatcher.end_game(game_id, player3);
    
    // Verify final state
    let (is_active, _, _, turn_count, _, is_started) = 
        dispatcher.get_game_state(game_id);
    
    assert(is_active == false, 'Game should be ended');
    assert(turn_count == 3, 'Should have 3 turns');
    assert(is_started == true, 'Game should be started');
}

#[test]
#[should_panic(expected: ('Game is not active',))]
fn test_join_inactive_game() {
    let contract_address = deploy_contract("UnoGame");
    let dispatcher = IUnoGameDispatcher { contract_address };

    let creator = starknet::contract_address_const::<0x123>();
    let player2 = starknet::contract_address_const::<0x456>();
    let player3 = starknet::contract_address_const::<0x789>();

    // Create and setup game
    let game_id = dispatcher.create_game(creator);
    
    // Add minimum required players
    dispatcher.join_game(game_id, player2);
    dispatcher.join_game(game_id, player3);
    
    // Start the game
    dispatcher.start_game(game_id);
    
    // End game on creator's turn
    dispatcher.end_game(game_id, player2);
    
    // Try to join the inactive game - should panic with 'Game is not active'
    dispatcher.join_game(game_id, player2);
}