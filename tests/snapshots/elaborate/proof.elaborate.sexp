(Unit main$1
  [(VarDecl x$1 int)
   (VarDecl y$2 int)
   (VarDecl g$3 int)
   (VarDecl s$4 int)
   (VarDecl $t1 int)
   (VarDecl i$5 int)]
  [(Assign x$1 (Int 2))
   (Check 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (BinOp * (Var x$1) (Var x$1)))
       (BinOp <= (BinOp * (Var x$1) (Var x$1)) (Int 9007199254740992))))
   (Assign y$2 (BinOp * (Var x$1) (Var x$1)))
   (Assign g$3 (BinOp * (Var x$1) (Var x$1)))
   (Assign s$4 (Int 0))
   (Assign $t1 (Var g$3))
   (Branch
     (BinOp <= (Int 1) (Var $t1))
     [(Assign i$5 (Int 1))
      (Check 2
        (BinOp and (BinOp <= (Int 1) (Var i$5)) (BinOp <= (Var i$5) (BinOp + (Var $t1) (Int 1)))))
      (Check 3 (BinOp >= (Var s$4) (Int 0)))
      (Block loop$1
        [(Havoc i$5)
         (Assume 1
           (BinOp and
             (BinOp <= (Int 1) (Var i$5))
             (BinOp <= (Var i$5) (BinOp + (Var $t1) (Int 1)))))
         (Havoc s$4)
         (Assume 2 (BinOp >= (Var s$4) (Int 0)))
         (Branch
           (BinOp <= (Var i$5) (Var $t1))
           [(Assign s$4 (BinOp + (Var s$4) (Var i$5)))
            (Assign i$5 (BinOp + (Var i$5) (Int 1)))
            (Check 4
              (BinOp and
                (BinOp <= (Int 1) (Var i$5))
                (BinOp <= (Var i$5) (BinOp + (Var $t1) (Int 1)))))
            (Check 5 (BinOp >= (Var s$4) (Int 0)))
            (Assume 3 (Bool false))]
           [])])]
     [])
   (Check 6 (BinOp == (Var g$3) (Int 4)))
   (Assume 4 (BinOp > (Var y$2) (Int 3)))])

(obligation 1 :kind range :node 6)
(obligation 2 :kind invariant_entry :node 31)
(obligation 3 :kind invariant_entry :node 31 :clause 21)
(obligation 4 :kind invariant_preserved :node 31)
(obligation 5 :kind invariant_preserved :node 31 :clause 21)
(obligation 6 :kind assert :node 36)

(assumption 1 :kind invariant :node 31)
(assumption 2 :kind invariant :node 21)
(assumption 3 :kind back_edge :node 31)
(assumption 4 :kind assumed :node 40)
