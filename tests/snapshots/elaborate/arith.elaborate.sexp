(Unit main$1 linear
  [(VarDecl x$1 int) (VarDecl y$2 int) (VarDecl z$3 int)]
  [(Assign x$1 (Int 127))
   (Check 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp - (Var x$1) (Int 2)))
       (BinOp <= (BinOp - (Var x$1) (Int 2)) (Int 9007199254740992))))
   (Check 2
     (BinOp and
       (BinOp <=
         (Int -9007199254740992)
         (BinOp * (BinOp - (Int 0) (Var x$1)) (BinOp - (Var x$1) (Int 2))))
       (BinOp <=
         (BinOp * (BinOp - (Int 0) (Var x$1)) (BinOp - (Var x$1) (Int 2)))
         (Int 9007199254740992))))
   (Check 3
     (BinOp and
       (BinOp <=
         (Int -9007199254740992)
         (BinOp + (BinOp * (BinOp - (Int 0) (Var x$1)) (BinOp - (Var x$1) (Int 2))) (Int -3)))
       (BinOp <=
         (BinOp + (BinOp * (BinOp - (Int 0) (Var x$1)) (BinOp - (Var x$1) (Int 2))) (Int -3))
         (Int 9007199254740992))))
   (Assign y$2 (BinOp + (BinOp * (BinOp - (Int 0) (Var x$1)) (BinOp - (Var x$1) (Int 2))) (Int -3)))
   (Check 4
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp + (Var y$2) (Int 1)))
       (BinOp <= (BinOp + (Var y$2) (Int 1)) (Int 9007199254740992))))
   (Assign z$3 (BinOp - (Int 0) (BinOp + (Var y$2) (Int 1))))])

(obligation 1 :kind range :node 8)
(obligation 2 :kind range :node 10)
(obligation 3 :kind range :node 13)
(obligation 4 :kind range :node 18)
