#!/usr/bin/env python

from azuremodules import *


import argparse
import os

parser = argparse.ArgumentParser()
parser.add_argument('-wl', '--whitelist', help='specify the xml file which contains the ignorable errors')

args = parser.parse_args()
white_list_xml = args.whitelist

def RunTest():
    UpdateState("TestRunning")
    RunLog.info("Checking for ERROR messages in waagent.log...")
    f = open('/var/log/waagent.log','r')
    content_list = f.readlines()
    f.close()
    errors_list = [x for x in content_list if 'error' in x.lower()]

    if (not errors_list) :
        RunLog.info('There is no errors in the logs waagent.log')
        ResultLog.info('PASS')
        UpdateState("TestCompleted")
    else :
        if white_list_xml and os.path.isfile(white_list_xml):
            try:
                import xml.etree.cElementTree as ET
            except ImportError:
                import xml.etree.ElementTree as ET

            white_list_file = ET.parse(white_list_xml)
            xml_root = white_list_file.getroot()
            RunLog.info('Checking ignorable walalog ERROR messages...')
            for node in xml_root:
                if (node.tag == "errors"):
                    for keywords in node:
                        RunLog.info('Scan ignorable error with pattern: "%s"' % keywords.text)
                        errors_list = [ x for x in errors_list if not re.match(keywords.text,x,re.IGNORECASE)]

        if (errors_list):
            RunLog.info('ERRORs are present in wala log.')
            RunLog.info('Errors: ')
            for x in errors_list:
                RunLog.info(x)
            ResultLog.error('FAIL')
        else:
            RunLog.info('ERRORs can be ignored in wala log')
            ResultLog.info('PASS')
        UpdateState("TestCompleted")
    
RunTest()