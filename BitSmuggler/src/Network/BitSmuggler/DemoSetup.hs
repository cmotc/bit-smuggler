{-# LANGUAGE OverloadedStrings #-}
module Network.BitSmuggler.DemoSetup where

import Prelude as P
import Data.Torrent
import Data.ByteString as BS
import Data.ByteString.Lazy as BSL
import System.FilePath.Posix
import Crypto.Random
import Crypto.Curve25519
import Data.Byteable
import Crypto.Random.AESCtr as AESCtr
import Data.IP
import Data.Serialize as DS
import Data.Map.Strict as Map
import Data.Binary as Bin
import qualified Network.BitTorrent.ClientControl as BT
import System.IO
import System.Log.Logger

import Data.Conduit.Binary as DC

import Network.BitSmuggler.Common as Common
import Network.BitSmuggler.Utils
import Network.BitSmuggler.TorrentFile
import Network.BitSmuggler.Crypto as Crypto
import Network.BitSmuggler.BitTorrentSimulator as Sim
import Network.BitSmuggler.Server as Server
import Network.BitSmuggler.Client as Client
import Network.BitSmuggler.FileCache as Cache

logger = "fakeClientTest"

setupFileCache = do
  contact <- makeContactFile
  fHandle <- openFile testDataFile ReadMode
  cache <- Cache.load serverCachePath
  Cache.put cache (infoHash contact) $  sourceHandle fHandle
  hClose fHandle
  Cache.close cache


runDemoClient = do
  updateGlobalLogger Client.logger  (setLevel DEBUG)
  updateGlobalLogger Sim.logger  (setLevel DEBUG)
  updateGlobalLogger Common.logger  (setLevel DEBUG)


  contact <- makeContactFile
  (serverDesc, _) <- makeServerDescriptor contact

  let connData = ConnectionData {
              connTorrent = BT.Torrent  (infoHash contact) $ takeFileName testDataFile
            , dataFile = streamFile
              -- no need for iptables redirection: we tell the bittorrent simulator
              -- to connect straight to the reverse proxy
            , peerAddr = (localhost, revProxyPort serverBTClientConfig)
            , proxyAddr = (localhost, socksProxyPort clientBTClientConfig)}

  proc <- simulatorProc clientBTRoot
           (Map.fromList [(Left $ takeFileName testDataFile, connData)])  streamFile

  let btC = clientBTClientConfig {btProc = proc}
  Client.clientConnect (ClientConfig btC serverDesc serverCachePath) $ \c -> do
    connSend c "hello from client"
    response <- connRecv c
    P.putStrLn $ show response

runDemoServer = do
  updateGlobalLogger Server.logger  (setLevel DEBUG)
  updateGlobalLogger Sim.logger  (setLevel DEBUG)
  updateGlobalLogger Common.logger  (setLevel DEBUG)

  contact <- makeContactFile
  (serverDesc, sk) <- makeServerDescriptor contact

  proc <- simulatorProc serverBTRoot Map.empty streamFile

  let btC = serverBTClientConfig {btProc = proc}
  Server.listen (ServerConfig sk btC [contact] clientCachePath) $ \c -> do
    message <- connRecv c
    P.putStrLn $ show message
    connSend c "hello from server"

    

root = "/home/dan/repos/bitSmuggler/bit-smuggler/demo"


clientBTRoot = root </> "client/utorrent-client"
serverBTRoot = root </> "server/utorrent-client"


clientCachePath = root </> "client/cache"
serverCachePath = root </> "server/cache"


streamFile = root </> "contactFile/testFileLenPrefixedStream"
testTFile = root </> "contactFile/testFile.torrent"

testDataFile = root </> "contactFile/testFile.txt"

makeContactFile = do
  Right t <- fmap readTorrent $ BSL.readFile $ testTFile 
  return $ FakeFile {seed = 23456, torrentFile = t
                    , infoHash = fromRight $ DS.decode $ computeInfoHash t}


makeServerDescriptor contact = do
  let cprg = cprgCreate $ createTestEntropyPool "leSeed" :: AESRNG
  let (skBytes, next2) = cprgGenerate Crypto.keySize cprg
  let serverSkWord = (fromRight $ DS.decode skBytes :: Key)
  let serverPk = derivePublicKey (fromBytes $ toBytes serverSkWord)
  let serverPkWord = (fromRight $ DS.decode (toBytes serverPk) :: Key)
  
  return $ (ServerDescriptor (IPv4 $ toIPv4 [127,0,0,1]) [contact] serverPkWord
            , serverSkWord)


clientBTClientConfig = BTClientConfig {
    pubBitTorrentPort = 5881
  , socksProxyPort = 2001
  , revProxyPort = 2002
  , cmdPort = 8000 -- port on which it's receiving commands
    -- host, port, (uname, password)
  , connectToClient = Sim.clientConn 
}

serverBTClientConfig = BTClientConfig {
    pubBitTorrentPort = 7881
  , socksProxyPort = 3001
  , revProxyPort = 3002
  , cmdPort = 9000 -- port on which it's receiving commands
    -- host, port, (uname, password)
  , connectToClient = Sim.clientConn 
}

