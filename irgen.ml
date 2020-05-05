module L = Llvm
open Ast
open Sast
open Pretty

(*
    *** Main concerns ***
      - How to implement list, array, and struct???
*)

let translate stmts =
  (* create the LLVM compilation module to which we will generate the code *)
  let context = L.global_context () in
  let the_module = L.create_module context "RattleSnake" in
  let builder = L.builder context in
  let local_vars:(string, L.llvalue) Hashtbl.t = Hashtbl.create 30 in
  let global_vars:(string, L.llvalue) Hashtbl.t = Hashtbl.create 30 in

  (* get types from context *)
  let i32_t      = L.i32_type    context
  and i8_t       = L.i8_type     context
  and i1_t       = L.i1_type     context
  and float_t    = L.double_type context
  and string_t   = L.pointer_type (L.i8_type context)
  and void_t     = L.void_type   context
  in (* TODO: add list, array, and struct *)

  let ltype_of_typ = function
    | Ast.Int -> i32_t
    | Ast.Bool -> i1_t
    | Ast.Float -> float_t
    | Ast.String -> string_t
    | Ast.Char -> string_t
    | Ast.Void -> i1_t
  in

  let printf_t : L.lltype = L.var_arg_function_type i32_t [| L.pointer_type i8_t |] in
  let printf_func : L.llvalue = L.declare_function "printf" printf_t the_module

  in
  (* this will act as a main function "wrapper" of sorts so that we can append blocks to it - trying to treat entire script as main function *)
  let main_ft = L.function_type i32_t [||] in
  let main_function = L.define_function "main" main_ft the_module in

  let builder = L.builder_at_end context (L.entry_block main_function) in

  let int_format_str = L.build_global_stringptr "%d\n" "int_fmt" builder in
  let str_format_str = L.build_global_stringptr "%s\n" "str_fmt" builder in
  let float_format_str = L.build_global_stringptr "%f\n" "str_fmt" builder in
  let char_format_str = L.build_global_stringptr "%s\n" "char_fmt" builder in
  let bool_format_str = L.build_global_stringptr "%d\n" "bool_fmt" builder in

  let lookup s =
    try Hashtbl.find local_vars s with (* check if s is a local variable *)
      | Not_found -> Hashtbl.find global_vars s

  in

  let rec build_expr builder ((t, e) : sexpr) =
    match e with
      | SIntLit i -> L.const_int i32_t i
      | SStrLit s -> L.build_global_stringptr s "string" builder
      | SBoolLit b -> L.const_int i1_t (if b then 1 else 0)
      | SFloatLit i -> L.const_float float_t i
      | SCharLit c -> L.build_global_stringptr c "char" builder
      | SId s -> L.build_load (lookup s) s builder
      | SBinop(e1, op, e2) -> (* TODO: going to need to handle case when adding different types, e.g. 2 + 5.5 *)
      	  (match t with		    (* LLVM will throw an error when types do not match *)
      	    | Ast.Float ->
      	      let e1' = build_expr builder e1
        	    and e2' = build_expr builder e2 in
        	  (match op with
          	  | Ast.Add -> L.build_fadd
          		| Ast.Sub -> L.build_fsub
          		| Ast.Div -> L.build_fdiv
          		| Ast.Mult-> L.build_fmul
          		| Ast.Mod -> L.build_frem
       		  ) e1' e2' "float_binop" builder
      	    | Ast.String ->
      	      let e1' = build_expr builder e1
        	    and e2' = build_expr builder e2 in
        	  (match op with
          		| Ast.Add -> raise (Failure ("string concatenation not yet implemented"))
          		| Ast.Eq -> L.build_icmp L.Icmp.Eq
          		| Ast.Neq -> L.build_icmp L.Icmp.Ne
          		| _ -> raise (Failure ("invalid operation on type string"))
        	  ) e1' e1' "string_binop" builder
        	| Ast.Bool -> (* TODO: make this compatible with comparing floats and ints *)
            let (t1, _) = e1
            and (t2, _) = e2 in
            match t1 with
              | Int ->
                (match t2 with
                  | Int ->
                    let e1' = build_expr builder e1
                    and e2' = build_expr builder e2 in
                    (match op with
                      | Ast.Eq -> L.build_icmp L.Icmp.Eq
                      | Ast.Neq -> L.build_icmp L.Icmp.Ne
                      | Ast.Gt -> L.build_icmp L.Icmp.Sgt
                      | Ast.Lt -> L.build_icmp L.Icmp.Slt
                      | Ast.Gte -> L.build_icmp L.Icmp.Sge
                      | Ast.Lte -> L.build_icmp L.Icmp.Sle
                    ) e1' e2' "bool_binop" builder
                  | Float ->
                    let int_e1 = build_expr builder e1 in
                    let e1' = L.build_sitofp int_e1 float_t "int_to_float" builder
                    and e2' = build_expr builder e2 in
                    (match op with
                      | Ast.Eq -> L.build_fcmp L.Fcmp.Oeq
                      | Ast.Neq -> L.build_fcmp L.Fcmp.One
                      | Ast.Gt -> L.build_fcmp L.Fcmp.Ogt
                      | Ast.Lt -> L.build_fcmp L.Fcmp.Olt
                      | Ast.Gte -> L.build_fcmp L.Fcmp.Oge
                      | Ast.Lte -> L.build_fcmp L.Fcmp.Ole
                    ) e1' e2' "bool_binop" builder)
              | Float ->
                (match t2 with
                  | Float ->
                    let e1' = build_expr builder e1
                    and e2' = build_expr builder e2 in
                    (match op with
                      | Ast.Eq -> L.build_fcmp L.Fcmp.Oeq
                      | Ast.Neq -> L.build_fcmp L.Fcmp.One
                      | Ast.Gt -> L.build_fcmp L.Fcmp.Ogt
                      | Ast.Lt -> L.build_fcmp L.Fcmp.Olt
                      | Ast.Gte -> L.build_fcmp L.Fcmp.Oge
                      | Ast.Lte -> L.build_fcmp L.Fcmp.Ole
                    ) e1' e2' "bool_binop" builder
                  | Int ->
                    let e1' = build_expr builder e1
                    and int_e2 = build_expr builder e2 in
                    let e2' = L.build_sitofp int_e2 float_t "int_to_float" builder in
                    (match op with
                      | Ast.Eq -> L.build_fcmp L.Fcmp.Oeq
                      | Ast.Neq -> L.build_fcmp L.Fcmp.One
                      | Ast.Gt -> L.build_fcmp L.Fcmp.Ogt
                      | Ast.Lt -> L.build_fcmp L.Fcmp.Olt
                      | Ast.Gte -> L.build_fcmp L.Fcmp.Oge
                      | Ast.Lte -> L.build_fcmp L.Fcmp.Ole
                    ) e1' e2' "bool_binop" builder)
              | Char -> raise (Failure ("not yet implemented"))
              | String -> raise (Failure ("not yet implemented"))
        	| Ast.Int ->
        	  let e1' = build_expr builder e1
        	  and e2' = build_expr builder e2 in
        	  (match op with
          	  | Ast.Add -> L.build_add
          		| Ast.Sub -> L.build_sub
          		| Ast.Div -> L.build_sdiv
          		| Ast.Mult-> L.build_mul
          		| Ast.Mod -> L.build_srem
       		  ) e1' e2' "int_binop" builder)
      | SUnop(id, unop) ->
        let var = lookup id in
        let var_val = L.build_load var "load" builder in
        if unop <> Not then
          raise (Failure ("invalide unary operation"))
        else L.build_not var_val "not" builder
      | SCall(name, args) ->
        let callee =
          match L.lookup_function name the_module with
            | Some c -> c
            | None -> raise (Failure ("unknown function referenced"))
        in
        let params = L.params callee
        and args_arr = Array.of_list args in
        if Array.length params <> Array.length args_arr then
          raise (Failure ("incorrect # of arguments passed"))
        else let args1 = Array.map (build_expr builder) args_arr in
        L.build_call callee args1 "call_func" builder
      (* TODO:
      | SAccess(id, e) ->
      | SSlice(id, e1, e1) ->
      *)

  in

  let rec build_body b f = function
    | [] -> b
    | _ as st :: tail ->
      let b' = build_stmt b f st in
      build_body b' f tail

  and build_dstmts b f end_bb = function
    | [] -> []
    | SElif(e, body) :: tail ->
      let elif_entry = L.append_block context "elif_entry" f in (* create an elif entry point bb *)
      let cond1 = build_expr (L.builder_at_end context elif_entry) e in
      let elif_bb = L.append_block context "elif_then" f in (* create bb for elif body *)
      ignore(L.move_block_after elif_bb end_bb);
      let res = build_dstmts b f end_bb tail in (* recursively build rest of dstmts from the bottom up *)
      if List.length res <> 0 then (* if there is dstmts following current elif, build conditional branch to other dstmts *)
        let next_bb = List.hd res in
        let b' = L.builder_at_end context elif_entry in
        ignore(L.build_cond_br cond1 elif_bb next_bb (L.builder_at_end context elif_entry));
      else ignore(L.build_cond_br cond1 elif_bb end_bb (L.builder_at_end context elif_entry)); (* otherwise build conditional branch to end_bb *)
      ignore(build_body (L.builder_at_end context elif_bb) f body); (* build elif body *)
      ignore(L.build_br end_bb (L.builder_at_end context elif_bb)); (* build branch to end_bb inside elif body, then return entrypoint *)
      [elif_entry]
    | SElse(body) :: tail -> (* there is always only one else at the very end *)
      let bb = L.append_block context "else" f in (* create bb for else body *)
      ignore(build_body (L.builder_at_end context bb) f body);
      ignore(L.build_br end_bb (L.builder_at_end context bb)); (* build branch to end_bb inside else body, then return bb *)
      ignore(L.move_block_after bb end_bb);
      [bb]
    | _ -> raise (Failure ("invalid dangling statement in if"))

    and build_stmt builder the_function = function
    | SExpr(e) -> ignore(build_expr builder e); builder
    | SBind(ty, id) ->
      let pointer = L.build_alloca (ltype_of_typ ty) id builder in
      Hashtbl.add global_vars id pointer;
      builder
  	| SFuncDef(func_def) -> (* TEST: no clue if this is right, tried to implement similar to microc *)
      Hashtbl.clear local_vars;
      let name = func_def.sfname in
      let params_arr = Array.of_list func_def.sformals in
      let params = Array.map (fun x ->
        match x with
          | (ty, id) -> ltype_of_typ ty
      ) params_arr in
      let ft = L.function_type (ltype_of_typ func_def.srtyp) params in (* define function type of return type and parameters *)
      let f = (* declare the function in the module *)
        match L.lookup_function name the_module with
          | None -> L.define_function name ft the_module
          | Some f -> raise (Failure ("function " ^ name ^ " is already defined"))
      in
      let func_builder = L.builder_at_end context (L.entry_block f) in
      let add_formal (t, n) p =
        L.set_value_name n p;
        let local = L.build_alloca (ltype_of_typ t) n func_builder in
        ignore(L.build_store p local func_builder);
        Hashtbl.add local_vars n local;
      and add_local (t, n) =
        let local_var = L.build_alloca (ltype_of_typ t) n func_builder in
        Hashtbl.add local_vars n local_var;
      in
      List.iter2 add_formal func_def.sformals (Array.to_list (L.params f));
      List.iter add_local func_def.slocals;
      let final_builder = build_body func_builder f func_def.sbody in
      if func_def.srtyp = Void then ignore(L.build_ret (L.const_int i1_t 1) final_builder);
      Hashtbl.clear local_vars;
      builder
  	| SIf(e, body, dstmts) -> (* TEST *)
      let entry = L.append_block context "if_entry" the_function in (* create entry point *)
      ignore (L.build_br entry builder);
      let cond = build_expr (L.builder_at_end context entry) e in
      let then_bb = L.append_block context "if_then" the_function in (* build block if conditional is true *)
      ignore(build_body (L.builder_at_end context then_bb) the_function body); (* generate code starting at end of then_bb *)
      let end_bb = L.append_block context "if_end" the_function in
      let build_br_end = L.build_br end_bb in (* builds a branch to end_bb *)
      let else_bb_lst = build_dstmts builder the_function end_bb dstmts in
      if List.length else_bb_lst > 0 then (* if there are dstmts, build a conditional branch to the other dstmts *)
        let else_bb = List.hd else_bb_lst in
        ignore(L.build_cond_br cond then_bb else_bb (L.builder_at_end context entry));
      else ignore(L.build_cond_br cond then_bb end_bb (L.builder_at_end context entry)); (* otherwise build conditional branch to end_bb *)
      ignore(L.build_br end_bb (L.builder_at_end context then_bb)); (* build branch to end_bb at end of then_bb *)
      L.builder_at_end context end_bb
  	| SWhile(e, body) -> (* TEST *)
      let entry_bb = L.append_block context "while_entry" the_function in (* build entry block *)
      ignore (L.build_br entry_bb builder);
      let cond = build_expr (L.builder_at_end context entry_bb) e in (* build conditional inside of entry block *)
      let while_body = L.append_block context "while_body" the_function in
      ignore(build_body (L.builder_at_end context while_body) the_function body); (* build body inside of while_body block *)
      let end_bb = L.append_block context "while_end" the_function in
      ignore(L.build_br entry_bb (L.builder_at_end context while_body)); (* branch to entry_bb at end of while_bb *)
      ignore(L.build_cond_br cond while_body end_bb (L.builder_at_end context entry_bb)); (* conditional branch to while_body or end_body at the end of entry_bb *)
      L.builder_at_end context end_bb
  	| SFor(var, e, body) -> (* TODO: no clue how to do this yet *)
      builder
  	| SRange(var, e, body) -> (* TEST *)
      let SBind(t, n) = var in
      let start_val = L.const_int i32_t 0 in (* create start val at 0 *)
      let iterator = L.build_alloca i32_t "iter" builder in (* allocate stack space for iterator var *)
      Hashtbl.add local_vars n iterator;
      ignore(L.build_store start_val iterator builder); (* store initial value for iterator *)
      let entry_bb = L.append_block context "range_entry" the_function in (* entry point *)
      ignore(L.build_br entry_bb builder);
      let body_bb = L.append_block context "range_body" the_function in
      ignore(build_body (L.builder_at_end context body_bb) the_function body); (* build body inside of body_bb *)
      let body_builder = L.builder_at_end context body_bb in
      let tmp_val = L.build_load iterator "load_iter" body_builder in (* load iterator value from stack space *)
      let next_val = L.build_add tmp_val (L.const_int i32_t 1) "next_val" body_builder in (* increment iterator value by 1 *)
      ignore(L.build_store next_val iterator body_builder); (* store incremented iterator value on stack *)
      ignore(L.build_br entry_bb body_builder); (* branch back to entry_bb *)
      let end_bb = L.append_block context "range_end" the_function in
      let end_val = build_expr builder e in
      let entry_builder = L.builder_at_end context entry_bb in
      let curr_val = L.build_load iterator "load_iter" entry_builder in (* in entry_bb, load value for iterator on stack *)
      let cond = L.build_icmp L.Icmp.Eq curr_val end_val "for_cmp" entry_builder in (* then check if it equals end_val *)
      ignore(L.build_cond_br cond end_bb body_bb entry_builder); (* conditional branch at end of entry_bb *)
      L.builder_at_end context end_bb
  	| SDo(body, e) ->
      let do_bb = L.append_block context "do_body" the_function in (* create main loop body block *)
      ignore(L.build_br do_bb builder); (* force it to execute at least once *)
      ignore(build_body (L.builder_at_end context do_bb) the_function body);
      let while_bb = L.append_block context "dowhile_cond" the_function in
      let end_bb = L.append_block context "do_end" the_function in
      let while_builder = L.builder_at_end context while_bb in
      let cond = build_expr while_builder e in
      ignore(L.build_cond_br cond do_bb end_bb while_builder); (* conditional branch at end of while_bb to either do_bb or end_bb *)
      ignore(L.build_br while_bb (L.builder_at_end context do_bb)); (* branch at end of do_bb to while_bb *)
      L.builder_at_end context end_bb
  	| SReturn(e) -> ignore(L.build_ret (build_expr builder e) builder); builder
  	| SAssign(s, e) ->
      let e' = build_expr builder e in
      let name = match s with
        | (t, SId(n)) -> n
      in
      ignore(L.build_store e' (lookup name) builder); builder (* build store function to load value into register *)
  	| SDecAssign(s, e) ->
      let (ty, id) = match s with
        | SBind(t, e) -> (t, e)
        | _ -> raise (Failure ("invalid declaration"))
      in
      let e' = build_expr builder e in
      let pointer = L.build_alloca (ltype_of_typ ty) id builder in
      Hashtbl.add global_vars id pointer;
      ignore(L.build_store e' pointer builder); builder (* build store function to load value into register *)
  	| SStruct(id, body) -> (* TODO: no clue how to do this yet *)
      builder
    | SPrint(e) ->
      (match e with
        | (Int, _) ->
          let e' = build_expr builder e in
          ignore(L.build_call printf_func [| int_format_str ; e' |] "printf" builder);
          builder
        | (String, _) ->
          let e' = build_expr builder e in
          ignore(L.build_call printf_func [| str_format_str ; e' |] "print_str" builder);
          builder
        | (Bool, _) ->
          let e' = build_expr builder e in
          ignore(L.build_call printf_func [| bool_format_str ; e' |] "print_bool" builder);
          builder
        | (Float, _) ->
          let e' = build_expr builder e in
          ignore(L.build_call printf_func [| float_format_str ; e' |] "print_float" builder);
          builder
        | (Char, _) ->
          let e' = build_expr builder e in
          ignore(L.build_call printf_func [| char_format_str ; e' |] "print_char" builder);
          builder)
  	| SCont -> builder
  	| SBreak -> builder
  	| SPass -> (* TODO *)
      builder

  in

  (*List.map (build_stmt builder main_function) stmts;*)
  let rec build_all_stmts b the_function = function
    | [] -> b
    | _ as st :: tail ->
      let b' = build_stmt b the_function st in
      build_all_stmts b' the_function tail
  in
  let final_builder = build_all_stmts builder main_function stmts in
  ignore (L.build_ret (L.const_int i32_t 0) final_builder);

  the_module
