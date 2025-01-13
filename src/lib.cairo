use starknet::ContractAddress;

#[starknet::interface]
pub trait IUnoGame<TContractState> {
    fn create_game(ref self: TContractState, creator: ContractAddress) -> u256;
    fn start_game(ref self: TContractState, game_id: u256);
    fn join_game(ref self: TContractState, game_id: u256, joinee: ContractAddress);
    fn submit_action(ref self: TContractState, game_id: u256, action_hash: felt252, actor: ContractAddress);
    fn end_game(ref self: TContractState, game_id: u256, actor: ContractAddress);
    fn get_game_state(self: @TContractState, game_id: u256) -> (bool, u256, u64, u256, bool, bool);
    fn get_active_games(self: @TContractState) -> Span<u256>;
    fn get_not_started_games(self: @TContractState) -> Span<u256>;
}

#[starknet::contract]
mod UnoGame {
use starknet::{ContractAddress, get_block_timestamp};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Map,
    };

    #[storage]
    struct Storage {
        _game_id_counter: u256,
        _active_games_count: u256,
        _active_games: Map<u256, u256>,
        games: Map<u256, Game>,
        game_players: Map<(u256, u32), ContractAddress>,
        game_actions: Map<(u256, u32), Action>,
        player_count: Map<u256, u32>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        GameCreated: GameCreated,
        PlayerJoined: PlayerJoined,
        GameStarted: GameStarted,
        ActionSubmitted: ActionSubmitted,
        GameEnded: GameEnded,
    }

    #[derive(Drop, starknet::Event)]
    struct GameCreated {
        #[key]
        game_id: u256,
        creator: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct PlayerJoined {
        #[key]
        game_id: u256,
        player: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct GameStarted {
        #[key]
        game_id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ActionSubmitted {
        #[key]
        game_id: u256,
        player: ContractAddress,
        action_hash: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct GameEnded {
        #[key]
        game_id: u256,
    }

    #[derive(Drop, starknet::Store)]
    struct Game {
        id: u256,
        is_active: bool,
        current_player_index: u256,
        last_action_timestamp: u64,
        turn_count: u256,
        direction_clockwise: bool,
        is_started: bool,
    }

    #[derive(Drop, starknet::Store)]
    struct Action {
        player: ContractAddress,
        action_hash: felt252,
        timestamp: u64,
    }

    mod Errors {
       pub const GAME_NOT_ACTIVE: felt252 = 'Game is not active';
       pub const GAME_ALREADY_STARTED: felt252 = 'Game already started';
       pub const NOT_ENOUGH_PLAYERS: felt252 = 'Not enough players';
       pub const GAME_FULL: felt252 = 'Game is full';
       pub const NOT_YOUR_TURN: felt252 = 'Not your turn';
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self._game_id_counter.write(0);
        self._active_games_count.write(0);
    }

    #[abi(embed_v0)]
    impl UnoGameImpl of super::IUnoGame<ContractState> {
        fn create_game(ref self: ContractState, creator: ContractAddress) -> u256 {
            let current_counter = self._game_id_counter.read();
            let new_game_id = current_counter + 1;
            self._game_id_counter.write(new_game_id);

            // Create seed and initial state hash like in Solidity
            let timestamp = get_block_timestamp();
        
            // Initialize new game
            let new_game = Game {
                id: new_game_id,
                is_active: true,
                current_player_index: 0,
                last_action_timestamp: timestamp,
                turn_count: 0,
                direction_clockwise: true,
                is_started: false,
            };

            self.games.write(new_game_id, new_game);
            
            // Add to active games
            let active_count = self._active_games_count.read();
            self._active_games.write(active_count, new_game_id);
            self._active_games_count.write(active_count + 1);
            
            // Initialize player count
            self.player_count.write(new_game_id, 0);

            self.emit(Event::GameCreated(GameCreated { game_id: new_game_id, creator }));
            new_game_id
        }

        fn start_game(ref self: ContractState, game_id: u256) {
            let mut game = self.games.read(game_id);
            assert(!game.is_started, Errors::GAME_ALREADY_STARTED);
            
            let player_count = self.player_count.read(game_id);

            assert(player_count >= 2, Errors::NOT_ENOUGH_PLAYERS);
            
            game.is_started = true;
            game.last_action_timestamp = get_block_timestamp();
            
            self.games.write(game_id, game);
            self.emit(Event::GameStarted(GameStarted { game_id }));
        }

        fn join_game(ref self: ContractState, game_id: u256, joinee: ContractAddress) {
            let game = self.games.read(game_id);
            assert(game.is_active, Errors::GAME_NOT_ACTIVE);
            
            let current_count = self.player_count.read(game_id);
            assert(current_count < 10, Errors::GAME_FULL);

            // Add player
            self.game_players.write((game_id, current_count), joinee);
            self.player_count.write(game_id, current_count + 1);

            self.emit(Event::PlayerJoined(PlayerJoined { game_id, player: joinee }));
        }

        fn submit_action(
            ref self: ContractState, 
            game_id: u256, 
            action_hash: felt252, 
            actor: ContractAddress
        ) {
            let mut game = self.games.read(game_id);
            assert(game.is_active, Errors::GAME_NOT_ACTIVE);
            assert(self.is_player_turn(game_id, actor), Errors::NOT_YOUR_TURN);

            // Record action
            let action = Action {
                player: actor,
                action_hash,
                timestamp: get_block_timestamp(),
            };
            self.game_actions.write((game_id, game.turn_count.try_into().unwrap()), action);

            // Update game state
            self.update_game_state(ref game);
            self.games.write(game_id, game);

            self.emit(Event::ActionSubmitted(ActionSubmitted { game_id, player: actor, action_hash }));
        }

        fn end_game(ref self: ContractState, game_id: u256, actor: ContractAddress) {
            let mut game = self.games.read(game_id);
            assert(game.is_active, Errors::GAME_NOT_ACTIVE);
            assert(self.is_player_turn(game_id, actor), Errors::NOT_YOUR_TURN);

            game.is_active = false;
            self.games.write(game_id, game);
            self.remove_from_active_games(game_id);
            
            self.emit(Event::GameEnded(GameEnded { game_id }));
        }

        fn get_game_state(
            self: @ContractState, 
            game_id: u256
        ) -> (bool, u256, u64, u256, bool, bool) {
            let game = self.games.read(game_id);
            (
                game.is_active,
                game.current_player_index,
                game.last_action_timestamp,
                game.turn_count,
                game.direction_clockwise,
                game.is_started
            )
        }

        fn get_active_games(self: @ContractState) -> Span<u256> {
            let count = self._active_games_count.read();
            let mut active_games = ArrayTrait::new();
            let mut i: u256 = 0;
            loop {
                if i >= count {
                    break;
                }
                active_games.append(self._active_games.read(i));
                i += 1;
            };
            active_games.span()
        }

        fn get_not_started_games(self: @ContractState) -> Span<u256> {
            let mut not_started = ArrayTrait::new();
            let count = self._active_games_count.read();
            let mut i: u256 = 0;
            
            loop {
                if i >= count {
                    break;
                }
                let game_id = self._active_games.read(i);
                let game = self.games.read(game_id);
                let player_count = self.player_count.read(game_id);
                
                if !game.is_started && player_count < 3 {
                    not_started.append(game_id);
                }
                i += 1;
            };
            not_started.span()
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn is_player_turn(self: @ContractState, game_id: u256, player: ContractAddress) -> bool {
            let game = self.games.read(game_id);
            let current_player = self.game_players.read(
                (game_id, game.current_player_index.try_into().unwrap())
            );
            current_player == player
        }

        fn update_game_state(ref self: ContractState, ref game: Game) {
            game.turn_count += 1;
            let player_count: u256 = self.player_count.read(game.id).into();
            game.current_player_index = (game.current_player_index + 1) % player_count;
            game.last_action_timestamp = get_block_timestamp();
        }

        fn remove_from_active_games(ref self: ContractState, game_id: u256) {
            let count = self._active_games_count.read();
            let mut i: u256 = 0;
            
            loop {
                if i >= count {
                    break;
                }
                if self._active_games.read(i) == game_id {
                    // Move last element to this position
                    let last_index = count - 1;
                    if i != last_index {
                        let last_game = self._active_games.read(last_index);
                        self._active_games.write(i, last_game);
                    }
                    self._active_games_count.write(last_index);
                    break;
                }
                i += 1;
            };
        }
    }
}