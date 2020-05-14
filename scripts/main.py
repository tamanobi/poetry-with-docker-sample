from app import Greeter
import argparse

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers()

    greeter = Greeter()
    parser_add = subparsers.add_parser("say")
    parser_add.add_argument("names", nargs="+", type=str)
    args = parser.parse_args()

    for name in args.names:
        greeting = greeter.say(name)
        print(greeting)
