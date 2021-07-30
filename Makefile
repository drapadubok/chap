run_local:
	cd src/chap; mix phx.server

docker_build:
	cd src/chap; DOCKER_BUILDKIT=1 docker build --progress=plain -t chap .
	docker tag chap drapabubok/chap:latest
	docker tag chap drapabubok/chap:$(COMMIT_HASH)
	docker push drapabubok/chap:latest
	docker push drapabubok/chap:$(COMMIT_HASH)
