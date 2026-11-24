(Unit main$1 linear
  [(VarDecl x$1 int) (VarDecl p$2 bool) (VarDecl q$3 bool)]
  [(Assign x$1 (Int 1))
   (Assign p$2
     (BinOp and
       (BinOp and
         (BinOp and (BinOp < (Var x$1) (Int 2)) (BinOp <= (Var x$1) (Int 2)))
         (BinOp > (Var x$1) (Int 0)))
       (BinOp >= (Var x$1) (Int 0))))
   (Assign q$3
     (BinOp and
       (BinOp and
         (BinOp and (BinOp == (Var x$1) (Int 1)) (BinOp != (Var x$1) (Int 2)))
         (BinOp == (Var p$2) (Bool true)))
       (BinOp != (Var p$2) (Bool false))))])
