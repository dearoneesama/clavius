(Unit main$1 linear
  [(VarDecl x$1 int) (VarDecl a$2 int) (VarDecl b$3 bool) (VarDecl x$4 int)]
  [(Assign x$1 (Int 1))
   (Assign a$2 (Var x$1))
   (Assign b$3 (Bool true))
   (Check 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp + (Var x$1) (Int 1)))
       (BinOp <= (BinOp + (Var x$1) (Int 1)) (Int 9007199254740992))))
   (Assign x$4 (BinOp + (Var x$1) (Int 1)))])

(obligation 1 :kind range :node 11)
