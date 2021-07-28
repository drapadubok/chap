import json
from datetime import datetime, timedelta

from clickhouse_driver import Client
import numpy as np


CH_HOST = "127.0.0.1"
CH_PORT = "9000"
CH_USERNAME = "dima"
CH_PASSWORD = "secret"
N = 1000000


experiment_simulation_config = [
    {
        "event_name": "visit",
        "distribution": np.random.binomial,
        "params": {
            "A": {"p": 0.8, "n": 1},
            "B": {"p": 0.8, "n": 1}
        }
    },
    {
        "event_name": "add_to_cart",
        "distribution": np.random.binomial,
        "params": {
            "A": {"p": 0.2, "n": 1},
            "B": {"p": 0.2, "n": 1}
        }
    },
    {
        "event_name": "open_cart",
        "distribution": np.random.binomial,
        "params": {
            "A": {"p": 0.8, "n": 1},
            "B": {"p": 0.8, "n": 1}
        }
    },
    {
        "event_name": "go_to_checkout",
        "distribution": np.random.binomial,
        "params": {
            "A": {"p": 0.1, "n": 1},
            "B": {"p": 0.5, "n": 1}
        }
    },
    {
        "event_name": "purchase",
        "distribution": np.random.binomial,
        "params": {
            "A": {"p": 0.1, "n": 1},
            "B": {"p": 0.1, "n": 1}
        }
    }
]


def simulate(to_file=False):
    print("Simulating experiment")
    json_dataset = []
    file_dataset = []
    for i in range(N):
        group = "A" if i > N / 2 else "B"
        dt = datetime.now()
        for e in experiment_simulation_config:
            dt += timedelta(minutes=1)
            draw = e["distribution"](**e["params"][group])
            if draw:
                json_dataset.append({"ts": dt, "event_name": e["event_name"], "uid": i, "variant": group})
                file_dataset.append(json.dumps({"ts": str(dt), "event_name": e["event_name"], "uid": i, "variant": group}))
            else:
                break
    print("Simulation done")
    if to_file:
        with open("dataset.json", "w") as fh:
            fh.write("\n".join(file_dataset))

    return json_dataset


if __name__ == "__main__":
    client = Client(host=CH_HOST, port=CH_PORT, user=CH_USERNAME, password=CH_PASSWORD)
    it_works = client.execute("SELECT 1")
    data = simulate()
    client.execute("INSERT INTO events FORMAT JSONEachRow", data, types_check=True)
