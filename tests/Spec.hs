{-# LANGUAGE FlexibleContexts #-}
module Main where

import Prelude as P
import Conduit
import Control.Monad (void, when, zipWithM_)
import Test.Hspec
import Data.Conduit.Tar
import System.Directory
import Data.ByteString as S
import System.IO
import System.FilePath
import Control.Exception

main :: IO ()
main =
    hspec $ do
        let stackWorkDir = ".stack-work"
        describe "tar/untar" $ do
            let tarUntarContent dir =
                    runConduitRes $
                    yield dir .| void tarFilePath .| untar (const (foldC >>= yield)) .| foldC
            before (collectContent "src") $ it "content" (tarUntarContent "src" `shouldReturn`)
        describe "tar/untar/tar" $ do
            around (withTempTarFiles stackWorkDir) $
                it "structure" $ \(fpIn, hIn, outDir, fpOut) -> do
                    writeTarball hIn [stackWorkDir]
                    hClose hIn
                    extractTarball fpIn (Just outDir)
                    curDir <- getCurrentDirectory
                    finally
                        (setCurrentDirectory outDir >> createTarball fpOut [stackWorkDir])
                        (setCurrentDirectory curDir)
                    tb1 <- readTarball fpIn
                    tb2 <- readTarball fpOut
                    P.length tb1 `shouldBe` P.length tb2
                    zipWithM_ shouldBe (fst <$> tb2) (fst <$> tb1)
                    zipWithM_ shouldBe (snd <$> tb2) (snd <$> tb1)

withTempTarFiles :: FilePath -> ((FilePath, Handle, FilePath, FilePath) -> IO c) -> IO c
withTempTarFiles base =
    bracket
        (do tmpDir <- getTemporaryDirectory
            (fp1, h1) <- openBinaryTempFile tmpDir (addExtension base ".tar")
            let outPath = dropExtension fp1 ++ ".out"
            return (fp1, h1, outPath, addExtension outPath ".tar")
        )
        (\(fp, h, dirOut, fpOut) -> do
             hClose h
             removeFile fp
             doesDirectoryExist dirOut >>= (`when` removeDirectoryRecursive dirOut)
             doesFileExist fpOut >>= (`when` removeFile fpOut)
        )


readTarball
  :: (MonadIO m, MonadThrow m, MonadBaseControl IO m) =>
     FilePath -> m [(FileInfo, Maybe ByteString)]
readTarball fp = runConduitRes $ sourceFileBS fp .| untar grabBoth .| sinkList
  where
    grabBoth fi =
        case fileType fi of
            FTNormal -> do
                content <- foldC
                yield (fi, Just content)
            _ -> yield (fi, Nothing)


collectContent :: FilePath -> IO (ByteString)
collectContent dir =
    runConduitRes $
    sourceDirectoryDeep False dir .| mapMC (\fp -> runConduit (sourceFileBS fp .| foldC)) .| foldC

