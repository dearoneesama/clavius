; fails: O1
; `local y = x + 1` for an int53 `x`. The second unit does the same under `if x < 100`.
(Unit add linear
  [(VarDecl x int) (VarDecl y int)]
  [(Assume 1 (BinOp and (BinOp <= (Int -9007199254740992) (Var x)) (BinOp <= (Var x) (Int 9007199254740992))))
   (Check 1 (BinOp and
     (BinOp <= (Int -9007199254740992) (BinOp + (Var x) (Int 1)))
     (BinOp <= (BinOp + (Var x) (Int 1)) (Int 9007199254740992))))
   (Assign y (BinOp + (Var x) (Int 1)))])
(Unit add_guarded linear
  [(VarDecl x int) (VarDecl y int)]
  [(Assume 2 (BinOp and (BinOp <= (Int -9007199254740992) (Var x)) (BinOp <= (Var x) (Int 9007199254740992))))
   (Branch (BinOp < (Var x) (Int 100))
     [(Check 2 (BinOp and
        (BinOp <= (Int -9007199254740992) (BinOp + (Var x) (Int 1)))
        (BinOp <= (BinOp + (Var x) (Int 1)) (Int 9007199254740992))))
      (Assign y (BinOp + (Var x) (Int 1)))]
     [])])

(obligation 1 :kind range :node 0)
(obligation 2 :kind range :node 0)

(assumption 1 :kind type_fact :node 0)
(assumption 2 :kind type_fact :node 0)
