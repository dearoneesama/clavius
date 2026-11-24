(Unit main$1 linear
  [(VarDecl x$1 int)]
  [(Assign x$1 (Int 1))
   (Check 1 (BinOp == (Var x$1) (Int 1)))
   (Check 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp + (Var x$1) (Int 1)))
       (BinOp <= (BinOp + (Var x$1) (Int 1)) (Int 9007199254740992))))
   (Check 3 (BinOp == (BinOp + (Var x$1) (Int 1)) (Int 2)))
   (Branch (BinOp > (Var x$1) (Int 1)) [(Check 4 (Bool false))] [])
   (Check 5 (Bool false))])

(obligation 1 :kind assert :node 8)
(obligation 2 :kind range :node 12)
(obligation 3 :kind assert :node 16)
(obligation 4 :kind unreachable :node 23)
(obligation 5 :kind unreachable :node 28)
