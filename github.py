#!/usr/bin/env python3

import argparse
import datetime
import json
import key
import pickle
import re
import sys
import time
import urllib.request


"""
Usage:

    # load saved data by default
    ./github.py -r 'embedded2015/arm-lecture' -s 2015-3-3T00:00:00 -e 2015-3-14T00:00:00


    # update saved data
    ./github.py -u -r 'embedded2015/arm-lecture' -s 2015-3-3T00:00:00 -e 2015-3-14T00:00:00

"""


lecture_repo = ''
start_time = ''
end_time = ''
student_list_file = 'student.txt'
student_list = []

# Debug
debug_mode = False


# Ref: https://stackoverflow.com/posts/969324/revisions
def isotime2datetime(t):
    return datetime.datetime.strptime(t[:-1], "%Y-%m-%dT%H:%M:%S")


def api_call(api):
    """
    github api call, return an empty list if there's an API call error
    """

    # note: only query for the first 100 items
    url = 'https://api.github.com/{}?per_page=100'.format(api)
    req = urllib.request.Request(url)
    req.add_header('Authorization', 'token {}'.format(key.OAUTH_KEY))

    try:
        if debug_mode: print('[+] API Call: {}'.format(url))
        doc = urllib.request.urlopen(req)

    except:
        if debug_mode: print('[-] GitHub API call error!')
        return []

    return json.loads(doc.read().decode())


def get_fork_repo(origin):
    """
    all repos forked from origin, BFS the fork tree
    """

    forked_repos = []
    search_list = [ origin ]

    while search_list:
        json = api_call('repos/{}/forks'.format(search_list[0]))
        forked_repos.append(search_list.pop(0))

        if json:
            search_list += [ obj['full_name'] for obj in json ]
            time.sleep(0.01)
        else:
            if debug_mode: print('[-] no forked repo found')

    # sort the result, case-insensitively
    return sorted(forked_repos, key=lambda s: s.lower())


def get_commit_log(repo):
    """
    git commit log from a specific repository
    """

    json = api_call('repos/{}/commits'.format(repo))

    log = [ { 'sha' : obj['sha'],
              'timestamp' : isotime2datetime(obj['commit']['committer']['date']),
              'message' :obj['commit']['message'] } for obj in json ]

    return log


def get_code_freqency(repo):
    """
    get weekly code frequency, additions and deletions
    """

    json = api_call('repos/{}/stats/code_frequency'.format(repo))

    freq = [ { 'timestamp' : datetime.date.fromtimestamp(int(obj[0])),
               'additions' : int(obj[1]),
               'deletions' : int(obj[2]) } for obj in json ]

    return freq


def get_comments(repo):
    """
    get comment list of a repository
    """
    json = api_call('repos/{}/comments'.format(repo))

    # let comments be sorted from new to old
    comments = reversed([ { 'username' : obj['user']['login'],
                            'url' : obj['html_url'],
                            'timestamp' : isotime2datetime(obj['updated_at']),
                            'body' : obj['body'] } for obj in json ])

    return comments


class Student(object):
    """
    stores all the info we need of a student
    """
    def __init__(self, repo):
        self.repo = repo
        self.commit_log = get_commit_log(self.repo)
        self.comments = get_comments(self.repo)
        # self.code_frequency = get_code_freqency(self.repo)


def print_with_commits(stu_l):
    for stu in stu_l:
        print("{:50}: {} commit(s)".format(stu['repo'] + ('(*)' if stu['repo'] in student_list else ''),
                                             len(stu['commits'])))


def print_with_comments(stu_l):
    for stu in stu_l:
        print("{:50}: {} comment(s)".format(stu['repo'] + ('(*)' if stu['repo'] in student_list else ''),
                                              len(stu['comments'])))

def get_student_id_list():
    repos = []
    try:
        with open(student_list_file) as f:
            repos = f.readlines()
            repos = [ line.strip() for line in repos ]
    except:
        # return an empty list here
        print('can\'t find {}'.format(student_list_file))

    return repos

# main
if __name__ == '__main__':

    student_list = get_student_id_list()

    # play with arguments, all are required
    parser = argparse.ArgumentParser()
    parser.add_argument("-u", "--update", action="store_true",
                        help="update saved data")
    parser.add_argument("-r", "--repo", action="store", required=True,
                        help="the repo to be analyzed, E.g. embedded2015/arm-lecture")
    parser.add_argument("-s", "--start", action="store", required=True,
                        help="the start of the assignment, E.g. 2015-3-1T00:00:00")
    parser.add_argument("-e", "--end", action="store", required=True,
                        help="the end of the assignment, E.g. 2015-3-1T00:00:00")
    args = parser.parse_args()

    # arguments checking
    m = re.search('(\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2})', args.start)
    if m:
        start_time = m.group(0) + 'Z'
    else:
        print('[-] invalid start time: {}'.format(args.start))
        sys.exit(1)

    m = re.search('(\d{4}-\d{1,2}-\d{1,2}T\d{2}:\d{2}:\d{2})', args.end)
    if m:
        end_time = m.group(0) + 'Z'
    else:
        print('[-] invalid end time: {}'.format(args.end))
        sys.exit(1)

    m = re.search('(\S+/\S+)', args.repo)
    if m:
        lecture_repo = m.group(0)
    else:
        print('[-] invalid repo: {}'.format(args.repo))
        sys.exit(1)

    if not (start_time and end_time and lecture_repo):
        print('[-] invalid arguments')
        sys.exit(1)

    # try to load saved student data
    if args.update:
        # go!
        print('[+] fetching data via Github API ... please wait')
        all_repos = get_fork_repo(lecture_repo)
        all_students = [ Student(repo) for repo in all_repos ]

    else:
        print('[+] load saved data, you might need -u option to update')
        try:
            all_repos, all_students = pickle.load(open('stu.save', 'rb'))
        except:
            print('[-] no saved data found, exit')
            sys.exit(1)

    for stu in student_list:
        if stu not in all_repos:
            print("[+] student repo {} is not in the fork tree".format(stu))



    print('[+] {} repos found'.format(len(all_repos)))
    print('[+] filter commits and comments between {} ~ {}'.format(start_time, end_time))
    print('\n' + '-'*20 + '\n')

    # timestamps should be converted to UTC
    start_time = isotime2datetime(start_time) - datetime.timedelta(hours=8)
    end_time = isotime2datetime(end_time) - datetime.timedelta(hours=8)
    three_days_later = start_time + datetime.timedelta(days=3)

    # filter out with the assignment time interval
    this_assinment = [
        { 'repo' : student.repo,
          'commits' : [ c for c in student.commit_log
                            if start_time <= c['timestamp'] < end_time]
        } for student in all_students ]

    this_assinment = sorted(this_assinment,
                            key=lambda s : len(s['commits']),
                            reverse=True)

    print("Top five by # of commits")
    print_with_commits(this_assinment[:5])
    print('\n' + '-'*20 + '\n')


    print("repos with 0 commit")
    print_with_commits([ student for student in this_assinment if len(student['commits']) == 0 ] )
    print('\n' + '-'*20 + '\n')


    # filter out from start to 3 datys later
    this_assinment_3days = [
        { 'repo' : student.repo,
          'commits' : [ c for c in student.commit_log \
                            if start_time <= c['timestamp'] < three_days_later]
        } for student in all_students ]

    this_assinment_3days = sorted(this_assinment_3days,
                                  key=lambda s : len(s['commits']),
                                  reverse=True)

    print('repos with 0 commit in three days')
    print_with_commits([ student for student in this_assinment_3days if len(student['commits']) == 0 ] )
    print('\n' + '-'*20 + '\n')


    print('all repos sorted by # of commits')
    print_with_commits(this_assinment)
    print('\n' + '-'*20 + '\n')


    this_assinment_comments = [
        { 'repo' : student.repo,
          'comments' : [ c for c in student.comments \
                            if start_time <= c['timestamp'] < end_time]
        } for student in all_students ]

    this_assinment_comments = sorted(this_assinment_comments,
                            key=lambda s : len(s['comments']),
                            reverse=True)

    print('all repos sorted by # of comments')
    print_with_comments(this_assinment_comments)
    print('\n' + '-'*20 + '\n')

    # save data
    try:
        pickle.dump([all_repos, all_students], open('stu.save', 'wb'))
    except:
        print('[-] can\'t save data, exit')
        sys.exit(1)
