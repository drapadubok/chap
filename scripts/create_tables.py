from clickhouse_driver import Client


CH_HOST = "127.0.0.1"
CH_PORT = "9000"
CH_USERNAME = "dima"
CH_PASSWORD = "secret"
N = 1000000

DDL_LOCAL = """
CREATE TABLE IF NOT EXISTS events_local on cluster '{cluster}' 
(
    ts DateTime64(6), 
    variant String, 
    event_name String, 
    uid Int32
) engine=ReplicatedMergeTree('/clickhouse/{installation}/{cluster}/tables/{shard}/{database}/{table}', '{replica}') 
PARTITION BY toYYYYMM(ts) 
ORDER BY (ts);
"""

DDL_DISTRIBUTED = """
CREATE TABLE IF NOT EXISTS events on cluster '{cluster}' AS events_local 
ENGINE = Distributed('{cluster}', default, events_local, rand());
"""


if __name__ == "__main__":
    client = Client(host=CH_HOST, port=CH_PORT, user=CH_USERNAME, password=CH_PASSWORD)
    it_works = client.execute("SELECT 1")
    client.execute(DDL_LOCAL)
    client.execute(DDL_DISTRIBUTED)
