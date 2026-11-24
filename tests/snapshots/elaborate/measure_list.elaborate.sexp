(Unit main$1 linear
  [(VarDecl i$1 int)
   (VarDecl j$2 int)
   (VarDecl $t1 int)
   (VarDecl $t2 int)
   (VarDecl k$3 int)
   (VarDecl $t3 int)
   (VarDecl $t4 int)
   (VarDecl $t5 int)]
  [(Assign i$1 (Int 0))
   (Assign j$2 (Int 0))
   (Check 1
     (BinOp and
       (BinOp and
         (BinOp and (BinOp <= (Int 0) (Var i$1)) (BinOp <= (Var i$1) (Int 3)))
         (BinOp <= (Int 0) (Var j$2)))
       (BinOp <= (Var j$2) (Int 3))))
   (Block loop$1
     [(Havoc j$2)
      (Assume 1
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var j$2))
          (BinOp <= (Var j$2) (Int 9007199254740992))))
      (Havoc i$1)
      (Assume 2
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var i$1))
          (BinOp <= (Var i$1) (Int 9007199254740992))))
      (Assume 3
        (BinOp and
          (BinOp and
            (BinOp and (BinOp <= (Int 0) (Var i$1)) (BinOp <= (Var i$1) (Int 3)))
            (BinOp <= (Int 0) (Var j$2)))
          (BinOp <= (Var j$2) (Int 3))))
      (Assign $t1 (BinOp - (Int 3) (Var i$1)))
      (Assign $t2 (BinOp - (Int 3) (Var j$2)))
      (Branch
        (BinOp < (Var i$1) (Int 3))
        [(Branch
           (BinOp < (Var j$2) (Int 3))
           [(Check 2
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var j$2) (Int 1)))
                (BinOp <= (BinOp + (Var j$2) (Int 1)) (Int 9007199254740992))))
            (Assign j$2 (BinOp + (Var j$2) (Int 1)))]
           [(Check 3
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var i$1) (Int 1)))
                (BinOp <= (BinOp + (Var i$1) (Int 1)) (Int 9007199254740992))))
            (Assign i$1 (BinOp + (Var i$1) (Int 1)))
            (Assign j$2 (Int 0))])
         (Check 4
           (BinOp and
             (BinOp and
               (BinOp and (BinOp <= (Int 0) (Var i$1)) (BinOp <= (Var i$1) (Int 3)))
               (BinOp <= (Int 0) (Var j$2)))
             (BinOp <= (Var j$2) (Int 3))))
         (Check 5
           (BinOp or
             (BinOp and
               (BinOp <= (Int 0) (Var $t1))
               (BinOp < (BinOp - (Int 3) (Var i$1)) (Var $t1)))
             (BinOp and
               (BinOp == (BinOp - (Int 3) (Var i$1)) (Var $t1))
               (BinOp and
                 (BinOp <= (Int 0) (Var $t2))
                 (BinOp < (BinOp - (Int 3) (Var j$2)) (Var $t2))))))
         (Assume 4 (Bool false))]
        [])])
   (Assign k$3 (Int 0))
   (Block loop$2
     [(Havoc k$3)
      (Assume 5
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var k$3))
          (BinOp <= (Var k$3) (Int 9007199254740992))))
      (Assign $t3 (Int 1))
      (Assign $t4 (BinOp - (Int 3) (Var k$3)))
      (Assign $t5 (Int 0))
      (Branch
        (BinOp < (Var k$3) (Int 3))
        [(Check 6
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Var k$3) (Int 1)))
             (BinOp <= (BinOp + (Var k$3) (Int 1)) (Int 9007199254740992))))
         (Assign k$3 (BinOp + (Var k$3) (Int 1)))
         (Check 7
           (BinOp or
             (BinOp and (BinOp <= (Int 0) (Var $t3)) (BinOp < (Int 1) (Var $t3)))
             (BinOp and
               (BinOp == (Int 1) (Var $t3))
               (BinOp or
                 (BinOp and
                   (BinOp <= (Int 0) (Var $t4))
                   (BinOp < (BinOp - (Int 3) (Var k$3)) (Var $t4)))
                 (BinOp and
                   (BinOp == (BinOp - (Int 3) (Var k$3)) (Var $t4))
                   (BinOp and (BinOp <= (Int 0) (Var $t5)) (BinOp < (Int 0) (Var $t5))))))))
         (Assume 6 (Bool false))]
        [])])])

(obligation 1 :kind invariant_entry :node 54 :clause 22)
(obligation 2 :kind range :node 39)
(obligation 3 :kind range :node 46)
(obligation 4 :kind invariant_preserved :node 54 :clause 22)
(obligation 5 :kind decrease :node 54 :clause 29)
(obligation 6 :kind range :node 70)
(obligation 7 :kind decrease :node 73 :clause 63)

(assumption 1 :kind type_fact :node 54)
(assumption 2 :kind type_fact :node 54)
(assumption 3 :kind invariant :node 22)
(assumption 4 :kind back_edge :node 54)
(assumption 5 :kind type_fact :node 73)
(assumption 6 :kind back_edge :node 73)
