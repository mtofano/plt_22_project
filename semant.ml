open Ast
open Sast
open Pretty

module StringMap = Map.Make(String)

let check stmts vars funcs =

	let type_of_var map id =
		try StringMap.find id map
		with Not_found -> raise (Failure ("undeclared identifier " ^ id))
	in

	let add_var map name ty =
	  match name with
	    | _ when StringMap.mem name map -> raise (Failure ("duplicate variable names"))
	    | _ -> StringMap.add name ty map

	in

	let check_assign lvt rvt err =
	  if lvt = rvt then lvt else raise (Failure (err))

	in

	let rec check_expr var_map func_map = function
	  | IntLit l -> (var_map, func_map, (Int, SIntLit l)) (* return type bindings for literals *)

	  | StrLit l -> (var_map, func_map, (String, SStrLit l))

	  | BoolLit l -> (var_map, func_map, (Bool, SBoolLit l))

	  | FloatLit l -> (var_map, func_map, (Float, SFloatLit l))

	  | CharLit l -> (var_map, func_map, (Char, SCharLit l))

	  | Id var -> (var_map, func_map, (type_of_var var_map var, SId var))

		| ListLit(e_lst) ->
		  let (_, _, (t, _)) = check_expr var_map func_map (List.hd e_lst) in
			let rec build_list_lit ty = function
			  | [] -> []
				| _ as st :: tail ->
				  let (_, _, (t1, e1)) = check_expr var_map func_map st in
					if t1 <> ty then raise (Failure ("types of list elements must match"))
					else (t1, e1) :: build_list_lit ty tail
			in
			let se_lst = build_list_lit t e_lst in
			(var_map, func_map, (t, SListLit(se_lst)))

		| ArrayLit(e_lst) ->
		  let (_, _, (t, _)) = check_expr var_map func_map (List.hd e_lst) in
			let rec build_arr_lit ty = function
			  | [] -> []
				| _ as st :: tail ->
				  let (_, _, (t1, e1)) = check_expr var_map func_map st in
					if t1 <> ty then raise (Failure("types of array elements must match"))
					else (t1, e1) :: build_arr_lit ty tail
			in
			let se_lst = build_arr_lit t e_lst in
			(var_map, func_map, (t, SArrayLit(se_lst)))

	  | Binop(ex1, op, ex2) -> (* check ex1 and ex2 recursively *)
	  	let (_, _, (t1, e1)) = check_expr var_map func_map ex1
	  	and (_, _, (t2, e2)) = check_expr var_map func_map ex2 in
	  	let err = "illegal binary operator " ^ string_of_op op in
	  	if t1 = t2 then
	  	  let t = match op with
	  	    | Add | Sub when t1 = Int -> Int
	  	    | Add | Sub when t1 = Float -> Float
	  	    | Add when t1 = String -> String
					| Add when t1 = Char -> String
	  	    | Mult when t1 = Int -> Int
	  	    | Mult when t1 = Float -> Float
	  	    | Exp when t1 = Int -> Int
	  	    | Exp when t1 = Float -> Float
	  	    | Div when t1 = Float -> Float
					| Div when t1 = Int -> Int
	  	    | Mod -> Int
	  	    | Eq | Neq -> Bool
	  	    | Lt | Gt | Lte | Gte when t1 = Int -> Bool
	  	    | Lt | Gt | Lte | Gte when t1 = Float -> Bool
	  	    | And | Or when t1 = Bool -> Bool
	  	    | _ -> raise (Failure err)
	  	  in
	  	  (var_map, func_map, (t, SBinop((t1, e1), op, (t2, e2))))
	  	else
	  	  let t = match op with
            | Add | Sub | Mult | Div | Exp when ((t1 = Int && t2 = Float) || (t1 = Float && t2 = Int)) -> Float
						| Add when ((t1 = String && t2 = Char) || (t1 = Char && t2 = String)) -> String
						| Eq | Neq | Gt | Lt | Lte | Gte when ((t1 = Int && t2 = Float) || (t1 = Float && t2 = Int)) -> Bool
						| In -> (match t2 with
							  | List(ty) when ty = t1 -> Bool
								| Array(ty, _) when ty = t1 -> Bool
								| String when t1 = Char -> Bool
								| _ -> raise (Failure ("types do not match")))
	  	      | _ -> raise (Failure err)
	  	  in
	  	  (var_map, func_map, (t, SBinop((t1, e1), op, (t2, e2))))

	  | Unop(var, un) -> (* check to ensure var is an id *)
	  	let ty = type_of_var var_map var in
	  	let t = match un with
	  	  | Not when ty = Bool -> Bool
	  	  | _ -> raise (Failure ("illegal unary operator on type "  ^ string_of_typ ty))
	  	in
	  	(var_map, func_map, (t, SUnop(var, un)))

	  | Call(fname, args) -> (* make sure arguments match types in func_def *)
	  	let fd = StringMap.find fname func_map in
	  	let param_length = List.length fd.sformals in
	  	if List.length args != param_length then
	  	  raise (Failure ("expected " ^ string_of_int param_length ^ " arguments"))
	  	else let check_call (ft, _) e =
	  	  let (_, _, (t, e')) = check_expr var_map func_map e in
	  	  let err = "illegal argument found " ^ string_of_typ t ^ " expected " ^ string_of_typ ft in
	  	  (check_assign ft t err, e')
	  	in
	  	let args' = List.map2 check_call fd.sformals args in
	  	(var_map, func_map, (fd.srtyp, SCall(fname, args')))

	  | Access(var, ex) -> (* ensure var is of list or array type and ex results in an int *)
	    let (_, _, (t1, e1)) = check_expr var_map func_map var
	    and (_, _, (t2, e2)) = check_expr var_map func_map ex in
	    if t2 = Int then
	      match t1 with
	        | List(ty) -> (var_map, func_map, (ty, SAccess((t1, e1), (t2, e2))))
	        | Array(ty, e) -> (var_map, func_map, (ty, SAccess((t1, e1), (t2, e2))))
					| String -> (var_map, func_map, (Char, SAccess((t1, e1), (t2, e2))))
	        | _ -> raise (Failure ("invalid access on non list/array/string type"))
			else raise (Failure ("list/array access index must be of type int"))

		| Index(id, e) ->
		  let (_, _, (t1, e1)) = check_expr var_map func_map id
			and (_, _, (t2, e2)) = check_expr var_map func_map e in
		  (match t1 with
			  | List(ty) ->
				  if t2 <> ty then raise (Failure ("expected expression of type " ^ string_of_typ ty ^ " but got expression of type " ^ string_of_typ t2))
					else  (var_map, func_map, (Int, SIndex((t1, e1), (t2, e2))))
				| _ -> raise (Failure ("index must be called on list type")))

		| Pop(id, e) ->
			let (_, _, (t1, e1)) = check_expr var_map func_map id
			and (_, _, (t2, e2)) = check_expr var_map func_map e in
			if t2 = Int then
				match t1 with
					| List(ty) -> (var_map, func_map, (ty, SPop((t1, e1), (t2, e2))))
					| _ -> raise (Failure ("pop must be called on list type"))
			else raise (Failure ("index must be of type int"))

		| Len(e) ->
		  let (_, _, (t1, e1)) = check_expr var_map func_map e in
			match t1 with
			  | String -> (var_map, func_map, (Int, SLen((t1, e1))))
				| List(ty) -> (var_map, func_map, (Int, SLen((t1, e1))))
				| Array(ty, sz) -> (var_map, func_map, (Int, SLen((t1, e1))))
				| _ -> raise (Failure ("len expression cannot be called with type " ^ string_of_typ t1))

	in

	let check_bool_expr var_map func_map ex =
		let (_, _, (t, e)) = check_expr var_map func_map ex in
		match t with
		  | Bool -> (t, e)
		  | _ -> raise (Failure ("expected expression of type bool but got " ^ string_of_typ t))

	in

	let rec check_func_params var_map func_map rty = function
	  | [] -> ([], var_map)
	  | Bind(t, s) as st :: tail ->
	    let (m, _, s) = check_stmt var_map func_map rty st in
	    let (t1, e1) = match s with
	      | SBind(t, e) -> (t, e)
	      | _ -> raise (Failure ("invalid function parameter"))
	    in
	    let ret = check_func_params m func_map rty tail in
	    ((t1, e1) :: fst ret, snd ret)
	  | _ -> raise (Failure ("illegal parameter in function definition"))

	and check_locals var_map func_map rty = function
		| [] -> ([], var_map)
		| Bind(t, s) :: tail ->
			let ret = check_locals var_map func_map rty tail in
			((t, s) :: fst ret, snd ret)
		| DecAssign(s, e) :: tail ->
			let (t, s) = (match s with
				| Bind(ty, n) -> (ty, n)
				| _ -> raise (Failure ("invalid declaration")))
			in
			let ret = check_locals var_map func_map rty tail in
			((t, s) :: fst ret, snd ret)
		| ArrayAssign(var, lit) :: tail ->
		  let (t, s) = (match var with
				| Bind(ty, n) -> (ty, n)
				| _ -> raise (Failure ("invalid declaration")))
			in
			let ret = check_locals var_map func_map rty tail in
			((t, s) :: fst ret, snd ret)
		| _ :: tail -> check_locals var_map func_map rty tail

	and check_stmt var_map func_map rty = function

	  | Expr ex -> let (_, _, (t, e)) = check_expr var_map func_map ex in (var_map, func_map, SExpr((t, e)))

	  | Bind(ty, st) ->
	    if ty <> Void then
			  (match ty with
				  | Array(t, e) ->
					  let (_, _, (t1, e1)) = check_expr var_map func_map e in
						if t1 <> Int then raise (Failure ("array initialization expected expression of type int but got expression of type " ^ string_of_typ t1))
						else
						let m = add_var var_map st ty in
						(m, func_map, SBind(ty, st))
					| _ ->
			      let m = add_var var_map st ty in
			      (m, func_map, SBind(ty, st)))
	    else raise (Failure ("cannot declare variable with void type"))

	  | FuncDef(vdec, formals, body) -> (* add func def to map *)
	  	let (ty, name) = (match vdec with
			  | Bind(t, n) -> (t, n)
				| _ -> raise (Failure ("invalid function declaration")))
	  	and (params, m1) = check_func_params StringMap.empty func_map rty formals in
			let (locals, m2) = check_locals m1 func_map rty body in
			let bod = check_stmt_list m2 func_map ty body in
	 	  let fdef = { srtyp=ty; sfname=name; sformals=params; slocals=locals; sbody=bod } in
	 	  let func_map' = StringMap.add name fdef func_map in
	 	  (var_map, func_map', SFuncDef(fdef))

	  | If(ex, st1_lst, st2_lst) ->
	    (var_map, func_map, SIf(check_bool_expr var_map func_map ex, check_stmt_list var_map func_map rty st1_lst, check_stmt_list var_map func_map rty st2_lst))

	  | Elif(ex, st_lst) -> (var_map, func_map, SElif(check_bool_expr var_map func_map ex, check_stmt_list var_map func_map rty st_lst))

	  | Else st_lst -> (var_map, func_map, SElse(check_stmt_list var_map func_map rty st_lst))

	  | While(ex, st_lst) -> (var_map, func_map, SWhile(check_bool_expr var_map func_map ex, check_stmt_list var_map func_map rty st_lst))

	  | For(st1, ex, st2_lst) -> (* check types of List elements rather than just checking for List *)
	    let (m, _, s) = check_stmt var_map func_map rty st1 in
	    let (t1, e1) = match s with
	      | SBind(t, e) -> (t, e)
	      | _ -> raise (Failure ("invalid variable declaration in for loop"))
	    and body = check_stmt_list m func_map rty st2_lst
	    and (_, _, (t2, e2)) = check_expr m func_map ex in
	    (match t2 with
			  | List(ty) when ty = t1 -> (m, func_map, SFor(s, (t2, e2), body))
				| Array(ty, e) when ty = t1 -> (m, func_map, SFor(s, (t2, e2), body))
				| String when t1 = Char -> (m, func_map, SFor(s, (t2, e2), body))
				| _ -> raise (Failure ("types of iterator variable and object elements do not match")))

	  | Range(st1, e1, e2, e3, st2_lst) ->
	  	let (m1, _, s1) = check_stmt var_map func_map rty st1 in
	  	let (t1, e1) = (match s1 with
			  | SBind(t, e) -> (t, e)
				| _ -> raise (Failure ("invalid range declaration")))
	  	and (_, _, (t2, e2)) = check_expr m1 func_map e1
			and (_, _, (t3, e3)) = check_expr m1 func_map e2
			and (_, _, (t4, e4)) = check_expr m1 func_map e3 in
	    let sst_lst = check_stmt_list m1 func_map rty st2_lst in
	  	if t1 = Int then
	  	  match t2 with
	  	    | Int when (t3 = Int && t4 = Int) -> (m1, func_map, SRange(s1, (t2, e2), (t3, e3), (t4, e4), sst_lst))
	  	    | _ -> raise (Failure ("for-range loop must be used with int types"))
	  	else raise (Failure("for-range loop must be used with int types"))

		| IRange(var, e, st_lst) ->
			let (m1, _, s1) = check_stmt var_map func_map rty var in
			let (t1, e1) = (match s1 with
			  | SBind(t, e) -> (t, e)
				| _ -> raise (Failure ("invalid irange declaration")))
			and (_, _, (t2, e2)) = check_expr m1 func_map e in
			let sst_lst = check_stmt_list m1 func_map rty st_lst in
			if t1 = Int then
				match t2 with
				  | List(ty) -> (m1, func_map, SIRange(s1, (t2, e2), sst_lst))
					| Array(ty, e) -> (m1, func_map, SIRange(s1, (t2, e2), sst_lst))
					| _ -> raise (Failure ("irange loop cannot be used with expression of type " ^ string_of_typ t2))
			else raise (Failure("for-irange loop must be used with variable of type int"))

	  | Do(st_lst, ex) -> (var_map, func_map, SDo(check_stmt_list var_map func_map rty st_lst, check_bool_expr var_map func_map ex))

	  | Return ex -> (* if return is not inside of a function definition then raise error *)
	  	let (_, _, (t, e)) = check_expr var_map func_map ex in
			if t = rty then (var_map, func_map, SReturn((t, e)))
			else raise (Failure ("invalid return type"))

	  | Assign(ex1, ex2) ->
	  	let (m1, _, (t1, e1)) = check_expr var_map func_map ex1 in
	  	let (m2, _, (t2, e2)) = check_expr m1 func_map ex2 in
	  	let err = "illegal assignment, expected expression of type " ^ string_of_typ t1 ^ " but got expression of type " ^ string_of_typ t2
	  	in
			(match t1 with
			  | List(ty) ->
				  (match (t2, e2) with
					  | (_, SListLit(s_lst)) ->
						  if ty = t2 then
							  match e1 with
								  | SId(s) -> (m2, func_map, SAssign((t1, e1), (t2, e2)))
									| _ -> raise (Failure ("can only assign to a variable"))
							else raise (Failure err)
						| (List(ty1), _) ->
						  if ty = ty1 then
							  match e1 with
								  | SId(s) -> (m2, func_map, SAssign((t1, e1), (t2, e2)))
									| _ -> raise (Failure ("can only assign to a variable"))
							else raise (Failure (err))
						| _ -> raise (Failure (err)))
				| Array(ty, sz) ->
				  let size = (match sz with
					  | IntLit(i) -> i
						| _ -> raise (Failure ("size of array must be an integer")))
					in
				  (match (t2, e2) with
						| (_, SArrayLit(s_lst)) ->
						  if List.length s_lst <> size then raise (Failure ("array literal must match size of array declaration"))
							else
							(match e1 with
								| SId(s) when ty = t2 -> (m2, func_map, SAssign((t1, e1), (t2, e2)))
								| _ -> raise (Failure ("must assign to a variable, the array types may be mismatched")))
						| (Array(ty1, sz1), _) ->
						  if (ty1 = ty) && (sz1 = sz) then (m2, func_map, SAssign((t1, e1), (t2, e2)))
							else raise (Failure (err))
						| _ -> raise (Failure (err)))
				| _ ->
				  (match e2 with
					  | SListLit(s_lst) -> raise (Failure ("cannot assign variable of type " ^ string_of_typ t1 ^ " to a list literal"))
						| SArrayLit(s_lst) -> raise (Failure ("cannot assign variable of type " ^ string_of_typ t1 ^ " to an array literal"))
						| _ ->
					  	if t1 = t2 then
					  	  match e1 with
					  	    | SId(s) -> (m2, func_map, SAssign((t1, e1), (t2, e2)))
									| SAccess(id, num) -> (m2, func_map, SAssign((t1, e1), (t2, e2)))
					  	    | _ -> raise (Failure ("can only assign to a variable"))
					  	else raise (Failure err)))

	  | DecAssign(st, ex) ->
	    let (m1, _, s) = check_stmt var_map func_map rty st in
	    let (t1, e1) = (match s with
			  | SBind(t, e) -> (t, e)
				| _ -> raise (Failure ("invalid declaration and assignment")))
	    and (m2, _, (t2, e2)) = check_expr m1 func_map ex in
	    let err = "illegal assignment, expected expression of type " ^ string_of_typ t1 ^ " but got expression of type " ^ string_of_typ t2
			in
			(match t1 with
			  | List(ty) ->
				  (match (t2, e2) with
					  | (_, SListLit(s_lst)) ->
						  if ty = t2 then (m2, func_map, SDecAssign(s, (t2, e2)))
							else raise (Failure err)
						| (List(ty1), _) ->
						  if ty = ty1 then (m2, func_map, SDecAssign(s, (t2, e2)))
							else raise (Failure err)
						| _ -> raise (Failure err))
				| Array(ty, sz) ->
				  (match (t2, e2) with
						| (Array(ty1, sz1), _) ->
						  if (ty1 = ty) && (sz1 = sz) then (m2, func_map, SDecAssign(s, (t2, e2)))
							else raise (Failure ("illegal assignment, expected expression of type " ^ string_of_typ t1 ^ " but got expression of type " ^ string_of_typ t2 ^ ", perhaps the sizes do not match"))
						| _ -> raise (Failure (err)))
				| _ ->
					if t1 = t2 then (m2, func_map, SDecAssign(s, (t2, e2)))
					else raise (Failure err))

		| ArrayAssign(st, e_lst) ->
		  let (m1, _, s) = check_stmt var_map func_map rty st in
			let (t1, e1) = match s with
			  | SBind(t, e) -> (t, e)
				| _ -> raise (Failure ("can only assign to a variable"))
			in
			let (arr_t, size) = match t1 with
			  | Array(t, IntLit(sz)) -> (t, sz)
				| _ -> raise (Failure ("cannot assign to array"))
			in
			let rec check_lit_list = function
			  | [] -> []
				| _ as e :: tail ->
				  let (_, _, (t2, e2)) = check_expr m1 func_map e in
					if t2 = arr_t then (t2, e2) :: check_lit_list tail
					else raise (Failure ("array literal expected type " ^ string_of_typ arr_t ^ " but got type " ^ string_of_typ t2))
			in
			let se_lst = check_lit_list e_lst in
			(m1, func_map, SArrayAssign(s, se_lst))

	  | Print ex -> (* ensure ex is valid for print *)
	    let (_, _, (t1, e1)) = check_expr var_map func_map ex in
	    let _ = match t1 with
	      | Int | Float | Bool | String | Char -> t1
				| List x -> t1
				| Array(x1, x2) -> t1
	      | _ -> raise (Failure ("cannot print expression of type " ^ string_of_typ t1))
	    in
	    (var_map, func_map, SPrint((t1, e1)))

		| Append(id, v) ->
		  let (_, _, (t1, e1)) = check_expr var_map func_map id in
			let lst_typ = match t1 with
			  | List(t) -> t
				| _ -> raise (Failure ("append needs to be called on a list type"))
			in
			let (_, _, (t2, e2)) = check_expr var_map func_map v in
			if lst_typ <> t2 then raise (Failure ("cannot append value of type " ^ string_of_typ t2 ^ " to list of type " ^ string_of_typ lst_typ))
			else (var_map, func_map, SAppend((t1, e1), (t2, e2)))

		| Remove(id, v) ->
			let (_, _, (t1, e1)) = check_expr var_map func_map id in
			let _ = (match t1 with
				| List(t) -> t
				| _ -> raise (Failure ("remove needs to be called on a list type")))
			in
			let (_, _, (t2, e2)) = check_expr var_map func_map v in
			if t2 <> Int then raise (Failure ("got expression of type " ^ string_of_typ t2 ^ " but expected expression of type int"))
			else (var_map, func_map, SRemove((t1, e1), (t2, e2)))

		| Insert(id, idx, v) ->
			let (_, _, (t1, e1)) = check_expr var_map func_map id in
			let lst_typ = match t1 with
				| List(t) -> t
				| _ -> raise (Failure ("insert needs to be called on a list type"))
			in
			let (_, _, (t2, e2)) = check_expr var_map func_map idx in
			if t2 <> Int then raise (Failure ("index must be of type int"))
			else let (_, _, (t3, e3)) = check_expr var_map func_map v in
			if lst_typ <> t3 then raise (Failure ("cannot insert value of type " ^ string_of_typ t2 ^ " to list of type " ^ string_of_typ lst_typ))
			else (var_map, func_map, SInsert((t1, e1), (t2, e2), (t3, e3)))

	  | Cont -> (var_map, func_map, SCont)

	  | Break -> (var_map, func_map, SBreak)

	  | Pass -> (var_map, func_map, SPass)

	  | _ -> raise (Failure ("invalid statement"))

	and check_stmt_list var_map func_map rty = function
	  | [] -> []
	  | s :: sl ->
	    let (var_map', func_map', st) = check_stmt var_map func_map rty s in
	    st :: check_stmt_list var_map' func_map' rty sl
	in
	check_stmt_list vars funcs Void stmts
