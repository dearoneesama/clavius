(Unit main$1 linear
  [(VarDecl x$1 int) (VarDecl y$2 int)]
  [(Assign x$1 (Int 1))
   (Branch
     (BinOp > (Var x$1) (Int 0))
     [(Check 1
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var x$1) (Int 1)))
          (BinOp <= (BinOp - (Var x$1) (Int 1)) (Int 9007199254740992))))
      (Assign x$1 (BinOp - (Var x$1) (Int 1)))]
     [(Check 2
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp + (Var x$1) (Int 1)))
          (BinOp <= (BinOp + (Var x$1) (Int 1)) (Int 9007199254740992))))
      (Branch
        (BinOp > (BinOp + (Var x$1) (Int 1)) (Int 0))
        [(Assign y$2 (Var x$1)) (Assign x$1 (Var y$2))]
        [(Assign x$1 (Int 0))])])
   (Branch (BinOp == (Var x$1) (Int 0)) [(Assign x$1 (Int 1))] [])])

(obligation 1 :kind range :node 10)
(obligation 2 :kind range :node 16)
