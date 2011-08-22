open Unix

(* OCaml has no epoll. What do you do if you have no epoll. Just Write it. *)
module Epoll = struct
  type t
  type flags
  type flag = 
    | IN
    | PRI
    | OUT
    | RDNORM
    | RDBAND
    | WRNORM
    | WRBAND
    | MSG
    | ERR
    | HUP
    | RDHUP
    | ONESHOT
    | ET 

  external make_flags : flag array -> flags = "caml_to_c_epoll_event_flags"
  external get_flags  : flags -> flag list  = "c_to_caml_epoll_event_flags"

  external create  : int -> t                         = "caml_epoll_create"
  external ctl_add : t -> file_descr -> flags -> unit = "caml_epoll_ctl_add"
  external ctl_mod : t -> file_descr -> flags -> unit = "caml_epoll_ctl_mod"
  external ctl_del : t -> file_descr -> unit          = "caml_epoll_ctl_del"

  external wait : t -> maxevents:int -> timeout:int -> (file_descr * flags) array = "caml_epoll_wait"
      (* CR jfuruse: 
         It creates an array, which causes lots of allocations. 
         We can optimize this by just copying the memory area and provide special iterator on it. *)
         
end

let port = 5000
let max_events = 1000

let setup_server_socket port =
  let sock = Unix.socket PF_INET SOCK_STREAM 0 in
  Unix.setsockopt sock SO_REUSEADDR true;
  let sin = ADDR_INET (Unix.inet_addr_any, port) in
  Unix.bind sock sin;
  Unix.listen sock 1024;
  sock

let unix_error_report e s1 s2 =
  Format.eprintf "Unix error: %s %s %s@."
    (Unix.error_message e)
    s1
    s2

module Conn = struct

  type t = Buffer.t

  let create () = Buffer.create 32
      
  let read_buffer_len = 1024
  let read_buffer = String.create read_buffer_len (* CR jfuruse: not good for multi-threading *)

  let read sock t =
    let rec read () = 
        let n = Unix.read sock read_buffer 0 read_buffer_len in
        if n = 0 then true (* end of input *)
        else begin
          Buffer.add_substring t read_buffer 0 n;
          read ()
        end
    in
    try
      read ()
    with
    | Unix_error (EAGAIN, _, _) -> false
    | Unix_error (e, s1, s2) -> unix_error_report e s1 s2; assert false

  let write sock t = 
    let s = Buffer.contents t in (* CR jfuruse: It copies the string. Bad. *)
    let slen = String.length s in
    let rec write from =
      try
        let n = Unix.write sock s from (slen - from) in
        let from = from + n in
        if from < slen then write from
        else begin
          Buffer.clear t;
          true
        end
      with
      | Unix_error (EAGAIN, _, _) -> 
          Buffer.clear t;
          Buffer.add_substring t s from (slen - from);
          false
      | Unix_error (e, s1, s2) -> unix_error_report e s1 s2; assert false
    in
    write 0

  let handle sock t =
    let read_done = read sock t in
    let write_done = write sock t in
    read_done && write_done
end

let main () =
  let procs = 1 in

  let listener = setup_server_socket port in
  prerr_endline "listening...";

  begin try 
    for i = 2 to procs do
      prerr_endline "Forking...";
      if Unix.fork () = 0 then raise Exit
    done
  with
  | Exit -> ()
  end;

  let epfd = Epoll.create 128 in

  let listener_flags = Epoll.make_flags [| Epoll.IN |] in
  Epoll.ctl_add epfd listener listener_flags;

  Format.eprintf "Listening port %d@." port;

  let client_flags = Epoll.make_flags [| Epoll.IN; Epoll.ET |] in

  let clients = Hashtbl.create 1031 in
  let tim_prev = ref (Unix.gettimeofday ()) in
  let proc = ref 0 in

  let rec loop () =
    let fd_flags_array = Epoll.wait epfd ~maxevents:max_events ~timeout:(-1) in
    
    Array.iter (fun (fd, flags) -> 

      if fd = listener then begin 
        (* event on listener *)
        let client, client_addr = Unix.accept listener in
        Unix.set_nonblock client;
        Epoll.ctl_add epfd client client_flags;
        Hashtbl.add clients client (Conn.create ());
(*
        Format.eprintf "connected: %d@." (Obj.magic client);
*)

      end else 
        (* event on client *)
        let conn = 
          try Hashtbl.find clients fd  with
          | Not_found -> Format.eprintf "Unknown fd %d@." (Obj.magic fd); assert false
        in
        let close () =
          Epoll.ctl_del epfd fd;
          Unix.close fd;
          Hashtbl.remove clients fd;
(*
          Format.eprintf "closed: %d@." (Obj.magic fd);
*)
        in
        try
          incr proc;
          if Conn.handle fd conn then close ()
        with
        | Not_found -> assert false
        | Unix_error (e, s1, s2) -> unix_error_report e s1 s2; assert false

    ) fd_flags_array;

    if !proc > 100000 then begin
      proc := 0;
      let tim = Unix.gettimeofday () in
      let d = tim -. !tim_prev in
      tim_prev := tim;
      Format.eprintf "%f reqs per sec@." (100000.0 /. d);
      loop ()
    end else loop ()
  in

  loop ()

let _ = main ()
