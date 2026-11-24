(Unit inc$1 linear
  [(VarDecl n$2 int) (VarDecl result$3 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$2))
       (BinOp <= (Var n$2) (Int 9007199254740992))))
   (Assume 2 (BinOp >= (Var n$2) (Int 0)))
   (Block body
     [(Check 1
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp + (Var n$2) (Int 1)))
          (BinOp <= (BinOp + (Var n$2) (Int 1)) (Int 9007199254740992))))
      (Assign result$3 (BinOp + (Var n$2) (Int 1)))
      (Check 2 (BinOp > (Var result$3) (Var n$2)))
      (Exit body)
      (Check 3 (Bool false))])])
(Unit main$1 linear
  [(VarDecl $t1 int) (VarDecl $t2 int) (VarDecl x$9 int) (VarDecl $t3 int) (VarDecl y$10 int)]
  [(Check 4 (BinOp >= (Int 1) (Int 0)))
   (Havoc $t1)
   (Assume 3
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var $t1))
       (BinOp <= (Var $t1) (Int 9007199254740992))))
   (Assume 4 (BinOp > (Var $t1) (Int 1)))
   (Check 5 (BinOp >= (Var $t1) (Int 0)))
   (Havoc $t2)
   (Assume 5
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var $t2))
       (BinOp <= (Var $t2) (Int 9007199254740992))))
   (Assume 6 (BinOp > (Var $t2) (Var $t1)))
   (Assign x$9 (Var $t2))
   (Assume 7 (BinOp > (Var x$9) (Int 1)))
   (Check 6 (BinOp >= (Var x$9) (Int 0)))
   (Havoc $t3)
   (Assume 8
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var $t3))
       (BinOp <= (Var $t3) (Int 9007199254740992))))
   (Assume 9 (BinOp > (Var $t3) (Var x$9)))
   (Assign y$10 (Var $t3))])

(obligation 1 :kind range :node 18)
(obligation 2 :kind post :node 19 :clause 11)
(obligation 3 :kind missing_return :node 21)
(obligation 4 :kind pre :node 62 :clause 7)
(obligation 5 :kind pre :node 63 :clause 7)
(obligation 6 :kind pre :node 73 :clause 39)

(assumption 1 :kind trusted :node 15 :decl 21)
(assumption 2 :kind trusted :node 7 :decl 21)
(assumption 3 :kind type_fact :node 62)
(assumption 4 :kind callee_post :node 62)
(assumption 5 :kind type_fact :node 63)
(assumption 6 :kind callee_post :node 63)
(assumption 7 :kind trusted :node 70 :decl 31)
(assumption 8 :kind trusted :node 73 :decl 57)
(assumption 9 :kind trusted :node 73 :decl 57)
