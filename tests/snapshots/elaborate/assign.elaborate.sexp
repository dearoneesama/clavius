(Unit main$1
  [(VarDecl a$1 int) (VarDecl b$2 int) (VarDecl $t1 int) (VarDecl $t2 int)]
  [(Assign a$1 (Int 1))
   (Assign b$2 (Int 2))
   (Check 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp + (Var a$1) (Var b$2)))
       (BinOp <= (BinOp + (Var a$1) (Var b$2)) (Int 9007199254740992))))
   (Assign a$1 (BinOp + (Var a$1) (Var b$2)))
   (Assign $t1 (Var b$2))
   (Assign $t2 (Var a$1))
   (Assign a$1 (Var $t1))
   (Assign b$2 (Var $t2))])

(obligation 1 :kind range :node 9)
