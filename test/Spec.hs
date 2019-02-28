{-# LANGUAGE FlexibleContexts, TypeFamilies, BlockArguments, ScopedTypeVariables #-}

import           AST
import           AST.Class.Recursive
import           AST.Class.Unify
import           AST.Infer
import           AST.Knot.Flip
import           AST.Term.NamelessScope
import           AST.Term.Nominal
import           AST.Term.Scheme
import           AST.Unify
import           Algebra.Lattice
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad.Except
import           Control.Monad.RWS
import           Control.Monad.ST
import           Data.Proxy
import           LangA.Pure
import           LangB.Pure
import           System.Exit (exitFailure)
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..))
import           TypeLang.Pure

lamXYx5 :: Tree Pure (LangA EmptyScope)
lamXYx5 = aLam \x -> aLam \_y -> x `aApp` (aLit 5 $:: intA)

infinite :: Tree Pure (LangA EmptyScope)
infinite = aLam \x -> x `aApp` x

skolem :: Tree Pure (LangA EmptyScope)
skolem = aLam \x -> x $:: forAll1 "a" \a -> a

validForAll :: Tree Pure (LangA EmptyScope)
validForAll = aLam id $:: forAll1 "a" \a -> a ~> a

nomLam :: Tree Pure (LangA EmptyScope)
nomLam =
    aLam \x -> x $:: s
    where
        s =
            mempty
            & Lens.at (Name "key") ?~ Pure TInt
            & Lens.at (Name "value") ?~ Pure TInt
            & QVarInstances
            & (`Types` QVarInstances mempty)
            & NominalInst (Name "Map")
            & TNom
            & Pure
            & uniType

letGen :: Tree Pure LangB
letGen = bLet "id" (lam "x" id) \i -> i $$ i $$ bLit 5

shouldNotGen :: Tree Pure LangB
shouldNotGen = lam "x" \x -> bLet "y" x id

simpleRec :: Tree Pure LangB
simpleRec = closedRec [("a", bLit 5)]

extendLit :: Tree Pure LangB
extendLit = recExtend [("a", bLit 5)] (bLit 7)

extendDup :: Tree Pure LangB
extendDup = closedRec [("a", bLit 7), ("a", bLit 5)]

extendGood :: Tree Pure LangB
extendGood = closedRec [("b", bLit 7), ("a", bLit 5)]

getAField :: Tree Pure LangB
getAField = lam "x" \x -> getField x "a"

vecApp :: Tree Pure LangB
vecApp =
    lam "x" \x -> lam "y" \y -> closedRec [("x", x), ("y", y)] & toNom "Vec"

usePhantom :: Tree Pure LangB
usePhantom = bLit 5 & toNom "PhantomInt"

unifyRows :: Tree Pure LangB
unifyRows =
    -- \f -> f {a : 5, b : 7} (f {b : 5, a : 7} 12)
    lam "f" \f ->
    (f $$ closedRec [("a", bLit 5), ("b", bLit 7)])
    $$
    ((f $$ closedRec [("b", bLit 5), ("a", bLit 7)]) $$ bLit 12)

inferExpr ::
    forall m t.
    ( Infer m t
    , Recursive Children t
    , Recursive (InferChildConstraints (Recursive (Unify m))) t
    ) =>
    Tree Pure t ->
    m (Tree Pure (TypeOf t))
inferExpr x =
    inferNode (wrap (Proxy :: Proxy Children) (Ann ()) x)
    >>= Lens.from _Flip (children (Proxy :: Proxy (Recursive (Unify m))) applyBindings)
    <&> (^. iType)

vecNominalDecl :: Tree Pure (NominalDecl Typ)
vecNominalDecl =
    Pure NominalDecl
    { _nParams =
        Types
        { _tRow = bottom
        , _tTyp = bottom & Lens.at (Name "elem") ?~ bottom
        }
    , _nScheme =
        Scheme
        { _sForAlls = Types bottom bottom
        , _sTyp = record [("x", tVar "elem"), ("y", tVar "elem")]
        }
    }

phantomIntNominalDecl :: Tree Pure (NominalDecl Typ)
phantomIntNominalDecl =
    Pure NominalDecl
    { _nParams =
        Types
        { _tRow = bottom
        , _tTyp = bottom & Lens.at (Name "phantom") ?~ bottom
        }
    , _nScheme =
        Scheme
        { _sForAlls = Types bottom bottom
        , _sTyp = Pure TInt
        }
    }

withNominals ::
    (Unify m Row, Unify m Typ, MonadReader env m) =>
    Lens.LensLike' Lens.Identity env (InferScope (UVarOf m)) -> m a -> m a
withNominals l act =
    do
        vec <- loadNominalDecl vecNominalDecl
        phantom <- loadNominalDecl phantomIntNominalDecl
        let addNoms x =
                x
                & Lens.at (Name "Vec") ?~ vec
                & Lens.at (Name "PhantomInt") ?~ phantom
        local (l . nominals %~ addNoms) act

prettyPrint :: Pretty a => a -> IO ()
prettyPrint = print . pPrint

testCommon ::
    (Pretty (Tree lang Pure)) =>
    Tree Pure lang ->
    String ->
    Either (Tree TypeError Pure) (Tree Pure Typ) ->
    Either (Tree TypeError Pure) (Tree Pure Typ) ->
    IO Bool
testCommon expr expect pureRes stRes =
    do
        putStrLn ""
        prettyPrint expr
        putStrLn "inferred to:"
        prettyPrint pureRes
        filter (not . fst) checks <&> snd & sequence_
        all fst checks & pure
    where
        checks =
            [ (Pretty.text expect == pPrint pureRes, putStrLn ("FAIL! Expected:\n" <> expect))
            , (pureRes == stRes, putStrLn "FAIL! Different result in ST:" *> prettyPrint stRes)
            ]

testA :: Tree Pure (LangA EmptyScope) -> String -> IO Bool
testA expr expect =
    testCommon expr expect pureRes stRes
    where
        pureRes = execPureInferA (inferExpr expr)
        stRes = runST (execSTInferA (inferExpr expr))

testB :: Tree Pure LangB -> String -> IO Bool
testB expr expect =
    testCommon expr expect pureRes stRes
    where
        pureRes = execPureInferB (withNominals id (inferExpr expr))
        stRes = runST (execSTInferB (withNominals Lens._1 (inferExpr expr)))

main :: IO ()
main =
    do
        numFails <-
            sequenceA tests
            <&> filter not <&> length
        putStrLn ""
        show numFails <> " tests failed out of " <> show (length tests) & putStrLn
        when (numFails > 0) exitFailure
    where
        tests =
            [ testA lamXYx5      "Right ((Int -> t0) -> t1 -> t0)"
            , testA infinite     "Left (t0 occurs in itself, expands to: t0 -> t1)"
            , testA skolem       "Left (SkolemEscape: t0)"
            , testA validForAll  "Right (t0 -> t0)"
            , testA nomLam       "Right (Map[key: Int, value: Int] -> Map[key: Int, value: Int])"
            , testB letGen       "Right Int"
            , testB shouldNotGen "Right (t0 -> t0)"
            , testB simpleRec    "Right (a : Int :*: {})"
            , testB extendLit    "Left (Mismatch Int r0)"
            , testB extendDup    "Left (ConstraintsViolation (a : Int :*: {}) (Forbidden fields: [a]))"
            , testB extendGood   "Right (b : Int :*: a : Int :*: {})"
            , testB unifyRows    "Right (((a : Int :*: b : Int :*: {}) -> Int -> Int) -> Int)"
            , testB getAField    "Right ((a : t0 :*: r0) -> t0)"
            , testB vecApp       "Right (t0 -> t0 -> Vec[elem: t0])"
            , testB usePhantom   "Right PhantomInt[phantom: t0]"
            ]

