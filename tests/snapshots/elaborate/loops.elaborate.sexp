(Unit f$1
  [(VarDecl n$2 int)
   (VarDecl result$3 int)
   (VarDecl i$4 int)
   (VarDecl s$5 int)
   (VarDecl $t1 int)
   (VarDecl $t2 int)
   (VarDecl j$6 int)
   (VarDecl $t3 int)
   (VarDecl k$7 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$2))
       (BinOp <= (Var n$2) (Int 9007199254740992))))
   (Assume 2 (BinOp and (BinOp >= (Var n$2) (Int 0)) (BinOp < (Var n$2) (Int 100))))
   (Block body
     [(Assign i$4 (Int 0))
      (Assign s$5 (Int 0))
      (Check 1 (BinOp <= (Var i$4) (Var n$2)))
      (Block loop$1
        [(Havoc i$4)
         (Assume 3
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var i$4))
             (BinOp <= (Var i$4) (Int 9007199254740992))))
         (Assume 4 (BinOp <= (Var i$4) (Var n$2)))
         (Assign $t1 (BinOp - (Var n$2) (Var i$4)))
         (Branch
           (BinOp < (Var i$4) (Var n$2))
           [(Branch (BinOp > (Var s$5) (Int 50)) [(Exit loop$1)] [])
            (Check 2
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var i$4) (Int 1)))
                (BinOp <= (BinOp + (Var i$4) (Int 1)) (Int 9007199254740992))))
            (Assign i$4 (BinOp + (Var i$4) (Int 1)))
            (Check 3 (BinOp <= (Var i$4) (Var n$2)))
            (Check 4
              (BinOp and
                (BinOp <= (Int 0) (Var $t1))
                (BinOp < (BinOp - (Var n$2) (Var i$4)) (Var $t1))))
            (Assume 5 (Bool false))]
           [])])
      (Block loop$2
        [(Havoc i$4)
         (Assume 6
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var i$4))
             (BinOp <= (Var i$4) (Int 9007199254740992))))
         (Assign $t2 (BinOp - (Var n$2) (Var i$4)))
         (Check 5
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Var i$4) (Int 1)))
             (BinOp <= (BinOp + (Var i$4) (Int 1)) (Int 9007199254740992))))
         (Assign j$6 (BinOp + (Var i$4) (Int 1)))
         (Assign i$4 (Var j$6))
         (Branch
           (BinOp >= (Var j$6) (Var n$2))
           []
           [(Check 6
              (BinOp and
                (BinOp <= (Int 0) (Var $t2))
                (BinOp < (BinOp - (Var n$2) (Var i$4)) (Var $t2))))
            (Assume 7 (Bool false))])])
      (Assign $t3 (Var n$2))
      (Branch
        (BinOp >= (Var $t3) (Int 1))
        [(Check 7
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Int 1) (Int -2)))
             (BinOp <= (BinOp + (Int 1) (Int -2)) (Int 9007199254740992))))
         (Assign k$7 (Var $t3))
         (Check 8
           (BinOp and
             (BinOp and
               (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
               (BinOp <= (Var k$7) (Var $t3)))
             (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
         (Check 9 (BinOp >= (Var s$5) (Int 0)))
         (Block loop$3
           [(Havoc k$7)
            (Assume 8
              (BinOp and
                (BinOp and
                  (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
                  (BinOp <= (Var k$7) (Var $t3)))
                (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
            (Havoc s$5)
            (Assume 9
              (BinOp and
                (BinOp <= (Int -9007199254740992) (Var s$5))
                (BinOp <= (Var s$5) (Int 9007199254740992))))
            (Assume 10 (BinOp >= (Var s$5) (Int 0)))
            (Branch
              (BinOp >= (Var k$7) (Int 1))
              [(Check 10
                 (BinOp and
                   (BinOp <= (Int -9007199254740992) (BinOp + (Var s$5) (Var k$7)))
                   (BinOp <= (BinOp + (Var s$5) (Var k$7)) (Int 9007199254740992))))
               (Assign s$5 (BinOp + (Var s$5) (Var k$7)))
               (Assign k$7 (BinOp + (Var k$7) (Int -2)))
               (Check 11
                 (BinOp and
                   (BinOp and
                     (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
                     (BinOp <= (Var k$7) (Var $t3)))
                   (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
               (Check 12 (BinOp >= (Var s$5) (Int 0)))
               (Assume 11 (Bool false))]
              [])])]
        [])
      (Assign result$3 (Var i$4))
      (Check 13 (BinOp == (Var result$3) (Var n$2)))
      (Exit body)
      (Check 14 (Bool false))])])

(obligation 1 :kind invariant_entry :node 50 :clause 29)
(obligation 2 :kind range :node 47)
(obligation 3 :kind invariant_preserved :node 50 :clause 29)
(obligation 4 :kind decrease :node 50 :clause 33)
(obligation 5 :kind range :node 57)
(obligation 6 :kind decrease :node 67 :clause 54)
(obligation 7 :kind for_bound :node 83)
(obligation 8 :kind invariant_entry :node 83)
(obligation 9 :kind invariant_entry :node 83 :clause 71)
(obligation 10 :kind range :node 80)
(obligation 11 :kind invariant_preserved :node 83)
(obligation 12 :kind invariant_preserved :node 83 :clause 71)
(obligation 13 :kind post :node 85 :clause 15)
(obligation 14 :kind missing_return :node 87)

(assumption 1 :kind trusted :node 19 :decl 87)
(assumption 2 :kind trusted :node 11 :decl 87)
(assumption 3 :kind type_fact :node 50)
(assumption 4 :kind invariant :node 29)
(assumption 5 :kind back_edge :node 50)
(assumption 6 :kind type_fact :node 67)
(assumption 7 :kind back_edge :node 67)
(assumption 8 :kind invariant :node 83)
(assumption 9 :kind type_fact :node 83)
(assumption 10 :kind invariant :node 71)
(assumption 11 :kind back_edge :node 83)
