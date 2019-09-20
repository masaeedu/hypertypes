{-# LANGUAGE TemplateHaskellQuotes #-}

-- | Generate 'KApply' and related instances via @TemplateHaskell@

module AST.TH.Apply
    ( makeKApply
    , makeKApplyAndBases
    , makeKApplicativeBases
    ) where

import           AST.Class.Apply
import           AST.TH.Functor (makeKFunctor)
import           AST.TH.Internal.Utils
import           AST.TH.Nodes (makeKNodes)
import           AST.TH.Pointed (makeKPointed)
import           Control.Applicative (liftA2)
import           Control.Lens.Operators
import           Data.Functor.Product.PolyKinds (Product(..))
import           Language.Haskell.TH

import           Prelude.Compat

-- | Generate instances of 'KApply',
-- 'AST.Class.Functor.KFunctor', 'AST.Class.Pointed.KPointed' and 'AST.Class.Nodes.KNodes',
-- which together form 'KApplicative'.
makeKApplicativeBases :: Name -> DecsQ
makeKApplicativeBases x =
    sequenceA
    [ makeKPointed x
    , makeKApplyAndBases x
    ] <&> concat

-- | Generate an instance of 'KApply'
-- along with its bases 'AST.Class.Functor.KFunctor' and 'AST.Class.Nodes.KNodes'
makeKApplyAndBases :: Name -> DecsQ
makeKApplyAndBases x =
    sequenceA
    [ makeKNodes x
    , makeKFunctor x
    , makeKApply x
    ] <&> concat

-- | Generate an instance of 'KApply'
makeKApply :: Name -> DecsQ
makeKApply typeName = makeTypeInfo typeName >>= makeKApplyForType

makeKApplyForType :: TypeInfo -> DecsQ
makeKApplyForType info =
    do
        (name, fields) <-
            case tiConstructors info of
            [x] -> pure x
            _ -> fail "makeKApply only supports types with a single constructor"
        let xVars = makeConstructorVars "x" fields
        let yVars = makeConstructorVars "y" fields
        instanceD (simplifyContext (makeContext info)) (appT (conT ''KApply) (pure (tiInstance info)))
            [ InlineP 'zipK Inline FunLike AllPhases & PragmaD & pure
            , funD 'zipK
                [ Clause
                    [ consPat name xVars
                    , consPat name yVars
                    ] (NormalB (foldl AppE (ConE name) (zipWith f xVars yVars))) []
                    & pure
                ]
            ]
            <&> (:[])
    where
        bodyForPat Node{} = ConE 'Pair
        bodyForPat Embed{} = VarE 'zipK
        bodyForPat (InContainer _ pat) = VarE 'liftA2 `AppE` bodyForPat pat
        bodyForPat PlainData{} = VarE '(<>)
        f (p, x) (_, y) =
            bodyForPat p `AppE` VarE x `AppE` VarE y

makeContext :: TypeInfo -> [Pred]
makeContext info =
    tiConstructors info >>= snd >>= ctxForPat
    where
        ctxForPat (InContainer t pat) = (ConT ''Applicative `AppT` t) : ctxForPat pat
        ctxForPat (Embed t) = [ConT ''KApply `AppT` t]
        ctxForPat (PlainData t) = [ConT ''Semigroup `AppT` t]
        ctxForPat _ = []
