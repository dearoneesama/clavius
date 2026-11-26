(Unit main$1 linear
  [(VarDecl $t1 int) (VarDecl $t2 int) (VarDecl x$1 int)]
  [(Havoc $t1)
   (Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var $t1))
       (BinOp <= (Var $t1) (Int 9007199254740992))))
   (Assume 2 (BinOp >= (Var $t1) (Int 0)))
   (Assume 3
     (BinOp or (BinOp == (Var $t1) (Int -3)) (BinOp == (Var $t1) (BinOp - (Int 0) (Int -3)))))
   (Havoc $t2)
   (Assume 4
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var $t2))
       (BinOp <= (Var $t2) (Int 9007199254740992))))
   (Assume 5 (BinOp and (BinOp >= (Var $t2) (Var $t1)) (BinOp >= (Var $t2) (Int 2))))
   (Assume 6 (BinOp or (BinOp == (Var $t2) (Var $t1)) (BinOp == (Var $t2) (Int 2))))
   (Assign x$1 (Var $t2))])

(assumption 1 :kind trusted :node 9 :decl 98)
(assumption 2 :kind trusted :node 9 :decl 98)
(assumption 3 :kind trusted :node 9 :decl 98)
(assumption 4 :kind trusted :node 11 :decl 74)
(assumption 5 :kind trusted :node 11 :decl 74)
(assumption 6 :kind trusted :node 11 :decl 74)
