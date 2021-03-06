type op = Add | Sub | Mult | Div | Mod | Exp | Eq | Neq | And | Or | Lt | Gt | Lte | Gte | In

type un = Not

(* expressions *)
type expr =
    IntLit of int
  | StrLit of string
  | BoolLit of bool
  | FloatLit of float
  | CharLit of string
  | ListLit of expr list
  | ArrayLit of expr list
  | Id of string
  | Binop of expr * op * expr
  | Unop of string * un
  | Call of string * expr list
  | Access of expr * expr
  | Index of expr * expr
  | Pop of expr * expr
  | Len of expr

type typ = Int | String | Bool | Float | Char | List of typ | Stct | Void | Array of typ * expr

(* statements *)
type stmt =
  | Expr of expr
  | Bind of typ * string
  | FuncDef of stmt * stmt list * stmt list
  | If of expr * stmt list * stmt list
  | Elif of expr * stmt list
  | Else of stmt list
  | While of expr * stmt list
  | For of stmt * expr * stmt list
  | Range of stmt * expr * expr * expr * stmt list
  | IRange of stmt * expr * stmt list
  | Do of stmt list * expr
  | Return of expr
  | Assign of expr * expr
  | DecAssign of stmt * expr
  | ArrayAssign of stmt * expr list
  | DecArr of stmt * expr list
  | Print of expr
  | Append of expr * expr
  | Remove of expr * expr
  | Insert of expr * expr * expr
  | Cont
  | Break
  | Pass

type program = stmt list
