(* IR generation: translate takes a semantically checked AST and
   produces LLVM IR

   LLVM tutorial: Make sure to read the OCaml version of the tutorial

   http://llvm.org/docs/tutorial/index.html

   Detailed documentation on the OCaml LLVM library:

   http://llvm.moe/
   http://llvm.moe/ocaml/

*)

module L = Llvm
module A = Ast
open Sast

module StringMap = Map.Make(String)

(* translate : Sast.program -> Llvm.module *)
let translate (globals, functions) =
  let context    = L.global_context () in

  (* Create the LLVM compilation module into which
     we will generate code *)
  let the_module = L.create_module context "RattleSnake" in

  (* Get types from the context *)
  let i32_t      = L.i32_type    context
  and i8_t       = L.i8_type     context
  and i1_t       = L.i1_type     context 
  and float_t    = L.double_type context 
  and string_t   = L.pointer_type (L.i8_type context)
  and void_t     = L.void_type   context
  in (* need list and struct *)

  (* Return the LLVM type for a MicroC type *)
  let ltype_of_typ = function
      A.Int    -> i32_t
    | A.Bool   -> i1_t
    | A.Float  -> float_t
    | A.String -> string_t
    | A.Char   -> i8_t
    | A.Void   -> void_t
  in (* need list and struct *)

  (* Create a map of global variables after creating each *)
  let global_vars : L.llvalue StringMap.t =
    let global_var m (t, n) =
      let init = match t with
          A.Float -> L.const_float (ltype_of_typ t) 0.0
        | _ -> L.const_int (ltype_of_typ t) 0
      in StringMap.add n (L.define_global n init the_module) m in
    List.fold_left global_var StringMap.empty globals in

  let printf_t : L.lltype =
    L.var_arg_function_type i32_t [| L.pointer_type i8_t |] in
  let printf_func : L.llvalue =
    L.declare_function "printf" printf_t the_module in

  (* Define each function (arguments and return type) so we can
     call it even before we've created its body *)
  let function_decls : (L.llvalue * sfunc_def) StringMap.t =
    let function_decl m fdecl =
      let name = fdecl.sfname
      and formal_types =
        Array.of_list (List.map (fun (t,_) -> ltype_of_typ t) fdecl.sformals)
      in let ftype = L.function_type (ltype_of_typ fdecl.srtyp) formal_types in
      StringMap.add name (L.define_function name ftype the_module, fdecl) m in
    List.fold_left function_decl StringMap.empty functions in

  (* Fill in the body of the given function *)
  let build_function_body fdecl =
    let (the_function, _) = StringMap.find fdecl.sfname function_decls in
    let builder = L.builder_at_end context (L.entry_block the_function) in

    let int_format_str = L.build_global_stringptr "%d\n" "fmt" builder
    and float_format_str = L.build_global_stringptr "%g\n" "fmt" builder 
    and string_format_str = L.build_global_stringptr "%s\n" "fmt" builder
    in

    (* Construct the function's "locals": formal arguments and locally
       declared variables.  Allocate each on the stack, initialize their
       value, if appropriate, and remember their values in the "locals" map *)
    let local_vars =
      let add_formal m (t, n) p =
        L.set_value_name n p;
        let local = L.build_alloca (ltype_of_typ t) n builder in
        ignore (L.build_store p local builder);
        StringMap.add n local m

      (* Allocate space for any locally declared variables and add the
       * resulting registers to our map *)
      and add_local m (t, n) =
        let local_var = L.build_alloca (ltype_of_typ t) n builder
        in StringMap.add n local_var m
      in

      let formals = List.fold_left2 add_formal StringMap.empty fdecl.sformals
          (Array.to_list (L.params the_function)) in
      List.fold_left add_local formals fdecl.slocals
    in

    (* Return the value for a variable or formal argument.
       Check local names first, then global names *)
    let lookup n = try StringMap.find n local_vars
      with Not_found -> StringMap.find n global_vars
    in

    (* Construct code for an expression; return its value *)
    let rec build_expr builder ((_, e) : sexpr) = match e with
        SIntLit i  -> L.const_int i32_t i
      | SFloatLit i  -> L.const_float float_t i
      | SStrLit s  -> L.build_global_stringptr s "string" builder
      | SBoolLit b  -> L.const_int i1_t (if b then 1 else 0)
      | SId s       -> L.build_load (lookup s) s builder
     
      | SBinop ((A.Float, _) as e1, op, e2) ->
        let e1' = build_expr builder e1
        and e2' = build_expr builder e2 in
        (match op with
           A.Add             -> L.build_fadd
         | A.Sub             -> L.build_fsub
         | A.Div             -> L.build_fdiv
         | A.Mult            -> L.build_fmul
         | A.Mod             -> L.build_frem
         | A.Eq              -> L.build_fcmp L.Fcmp.Oeq
         | A.Neq             -> L.build_fcmp L.Fcmp.One
         | A.Lt              -> L.build_fcmp L.Fcmp.Olt
         | A.Gt              -> L.build_fcmp L.Fcmp.Ogt
         | A.Lte             -> L.build_fcmp L.Fcmp.Ole
         | A.Gte             -> L.build_fcmp L.Fcmp.Oge
        ) e1' e2' "tmp" builder
      | SBinop ((A.String, _) as e1, op, e2) ->
        let e1' = build_expr builder e1
        and e2' = build_expr builder e2 in
        (match op with
           A.Add     ->  raise(Failure("Not yet implemented"))(* todo: concat strings *)
        )
      | SBinop (e1, op, e2) ->
        let e1' = build_expr builder e1
        and e2' = build_expr builder e2 in
        (match op with
           A.Add             -> L.build_add
         | A.Sub             -> L.build_sub
         | A.Div             -> L.build_sdiv
         | A.Mult             -> L.build_mul
         | A.Mod             -> L.build_srem
         | A.And             -> L.build_and
         | A.Or              -> L.build_or
         | A.Eq           -> L.build_icmp L.Icmp.Eq
         | A.Neq             -> L.build_icmp L.Icmp.Ne
         | A.Lt            -> L.build_icmp L.Icmp.Slt
         | A.Gt         -> L.build_icmp L.Icmp.Sgt
         | A.Lte       -> L.build_icmp L.Icmp.Sle
         | A.Gte    -> L.build_icmp L.Icmp.Sge
        ) e1' e2' "tmp" builder
      
      | SCall ("print", [e]) ->
        L.build_call printf_func [| int_format_str ; (build_expr builder e) |]
          "printf" builder
      | SCall ("printf", [e]) ->
        L.build_call printf_func [| float_format_str ; (build_expr builder e) |]
          "printf" builder
      | SCall ("prints", [e]) ->
        L.build_call printf_func [| string_format_str ; (build_expr builder e) |]
          "printf" builder
      | SCall (f, args) ->
        let (fdef, fdecl) = StringMap.find f function_decls in
        let llargs = List.rev (List.map (build_expr builder) (List.rev args)) in
        let result = f ^ "_result" in
        L.build_call fdef (Array.of_list llargs) result builder
    in

    (* LLVM insists each basic block end with exactly one "terminator"
       instruction that transfers control.  This function runs "instr builder"
       if the current block does not already have a terminator.  Used,
       e.g., to handle the "fall off the end of the function" case. *)
    
    (* Build the code for the given statement; return the builder for
       the statement's successor (i.e., the next instruction will be built
       after the one generated by this call) *)
    

    (* Add a return if the last block falls off the end *)
    

  in

  List.iter build_function_body functions;
  the_module
