use futures::channel::mpsc::Sender;
use std::mem;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use bo::*;
use db_ops::*;

pub fn process_request(
    input: &str,
    sender: &mut Sender<String>,
    db: &Arc<SelectedDatabase>,
    dbs: &Arc<Databases>,
    auth: &Arc<AtomicBool>,
) -> Response {
    println!(
        "[{}] process_request got message '{}'. ",
        thread_id::get(),
        input
    );
    let start = Instant::now();
    let request = match Request::parse(String::from(input).trim_matches('\n')) {
        Ok(req) => req,
        Err(e) => return Response::Error { msg: e },
    };
    println!(
        "[{}] process_request parsed message '{}'. ",
        thread_id::get(),
        input
    );
    let result = match request {
        Request::Auth { user, password } => {
            let valid_user = dbs.user.clone();
            let valid_pwd = dbs.pwd.clone();

            if user == valid_user && password == valid_pwd {
                auth.swap(true, Ordering::Relaxed);
            };
            let message = if auth.load(Ordering::SeqCst) {
                "valid auth\n".to_string()
            } else {
                "invalid auth\n".to_string()
            };
            match sender.clone().try_send(message) {
                Ok(_n) => (),
                Err(e) => println!("Request::Auth sender.send Error: {}", e),
            }

            return Response::Ok {};
        }

        Request::Get { key } => {
            apply_to_database(&dbs, &db, &sender, &|_db| get_key_value(&key, &sender, _db))
        },

        Request::Set { key, value } => apply_to_database(&dbs, &db, &sender, &|_db| {
            set_key_value(key.clone(), value.clone(), _db)
        }),

        Request::Snapshot {} => apply_if_auth(auth, &|| {
            apply_to_database(&dbs, &db, &sender, &|_db| snapshot_db(_db, &dbs))
        }),

        Request::UnWatch { key } => {
            apply_to_database(&dbs, &db, &sender, &|_db| {
                unwatch_key(&key, &sender, _db);
                Response::Ok {}
            })
        },

        Request::UnWatchAll {} => {
            apply_to_database(&dbs, &db, &sender, &|_db| {
                unwatch_all(&sender, _db);
                Response::Ok {}
            })
        },

        Request::Watch { key } => {
            apply_to_database(&dbs, &db, &sender, &|_db| {
                watch_key(&key, &sender, _db);
                Response::Ok {}
            })
        },






        Request::UseDb { name, token } =>  {
            let mut db_name_state = db.name.lock().expect("Could not lock name mutex");
            let dbs = dbs.map.lock().expect("Could not lock the map mutex");
            let respose: Response = match dbs.get(&name.to_string()) {
                Some(db) => {
                    if is_valid_token(&token, db) {
                        mem::replace(&mut *db_name_state, name.clone());
                        Response::Ok {}
                    } else {
                        Response::Error {
                            msg: "Invalid token".to_string(),
                        }
                    }
                }
                _ => {
                    println!("Not a valid database name");
                    Response::Error {
                        msg: "Not a valid database name".to_string(),
                    }
                }
            };
            respose
        },

        Request::CreateDb { name, token } => apply_if_auth(&auth, &|| {
            let mut dbs = dbs.map.lock().unwrap();
            let empty_db_box = create_temp_db(name.clone());
            let empty_db = Arc::try_unwrap(empty_db_box);
            match empty_db {
                Ok(db) => {
                    set_key_value(TOKEN_KEY.to_string(), token.clone(), &db);
                    dbs.insert(name.to_string(), db);
                    match sender.clone().try_send("create-db success\n".to_string()) {
                        Ok(_n) => (),
                        Err(e) => println!("Request::CreateDb  Error: {}", e),
                    }
                }
                _ => {
                    println!("Could not create the database");
                    match sender
                        .clone()
                        .try_send("error create-db-error\n".to_string())
                    {
                        Ok(_n) => (),
                        Err(e) => println!("Request::Set sender.send Error: {}", e),
                    }
                }
            }
            Response::Ok {}
        }),
    };

    let elapsed = start.elapsed();
    println!(
        "[{}] Server processed message '{}' in {:?}",
        thread_id::get(),
        input,
        elapsed
    );
    result
}
