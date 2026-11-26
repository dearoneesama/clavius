(Unit main$1 linear [(VarDecl x$2 int)] [(Assign x$2 (Int 1))])
(Unit main$2 linear
  [(VarDecl main$3 int)]
  [(Assign main$3 (Int 2)) (Check 1 (BinOp == (Var main$3) (Int 2)))])
(Unit square$4 nonlinear
  [(VarDecl n$5 int) (VarDecl result$6 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$5))
       (BinOp <= (Var n$5) (Int 9007199254740992))))
   (Block body
     [(Check 2
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp * (Var n$5) (Var n$5)))
          (BinOp <= (BinOp * (Var n$5) (Var n$5)) (Int 9007199254740992))))
      (Assign result$6 (BinOp * (Var n$5) (Var n$5)))
      (Exit body)
      (Check 3 (Bool false))])])
(Unit square_spec$7 nonlinear
  [(VarDecl n$8 int) (VarDecl result$9 bool)]
  [(Assume 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$8))
       (BinOp <= (Var n$8) (Int 9007199254740992))))
   (Block body
     [(Assign result$9 (BinOp == (BinOp * (Var n$8) (Var n$8)) (BinOp * (Var n$8) (Var n$8))))
      (Exit body)
      (Check 4 (Bool false))])])
(Unit main$3 nonlinear
  [(VarDecl y$10 int)]
  [(Check 5
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp * (Int 1) (Int 2)))
       (BinOp <= (BinOp * (Int 1) (Int 2)) (Int 9007199254740992))))
   (Assign y$10 (BinOp * (Int 1) (Int 2)))])

(obligation 1 :kind assert :node 19)
(obligation 2 :kind range :node 29)
(obligation 3 :kind missing_return :node 32)
(obligation 4 :kind missing_return :node 49)
(obligation 5 :kind range :node 54)

(assumption 1 :kind trusted :node 26 :decl 32)
(assumption 2 :kind precondition :node 39)
